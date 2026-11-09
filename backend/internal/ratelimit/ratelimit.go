// package ratelimit caps how fast one caller can hit the api.
//
// **in-memory and per-process, which bounds what it can promise**: two instances behind a load
// balancer each enforce their own budget, so the effective rate doubles. right at one server, wrong
// the day there are two - at which point this belongs in nginx or Cloudflare. a floor, not a perimeter.
package ratelimit

import (
	"encoding/json"
	"fmt"
	"math"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// a token bucket per client, refilled continuously. a bucket rather than a fixed window, because a
// window resets on a wall-clock edge: 60/minute allows 60 at 11:59:59 and 60 more at 12:00:00.
type Limiter struct {
	rate  float64 // tokens earned per second
	burst float64 // most tokens a bucket can hold

	// who to bucket a request under. nil means the caller's network address.
	identity func(*http.Request) string

	mu      sync.Mutex
	buckets map[string]*bucket
}

type bucket struct {
	tokens float64
	seen   time.Time
}

// `rate` per second sustained with room for `burst` in one go, plus a sweeper that forgets clients
// idle longer than `idleTTL` - without it every distinct IP is an entry the map never gives back.
func New(rate float64, burst int, idleTTL time.Duration) *Limiter {
	l := &Limiter{
		rate:    rate,
		burst:   float64(burst),
		buckets: make(map[string]*bucket),
	}
	go l.sweep(idleTTL)
	return l
}

// Allow reports whether this client may make one more request now, and spends a token if so.
func (l *Limiter) Allow(client string) bool {
	now := time.Now()

	l.mu.Lock()
	defer l.mu.Unlock()

	b, known := l.buckets[client]
	if !known {
		// a new client starts full, so a first request is never rejected
		l.buckets[client] = &bucket{tokens: l.burst - 1, seen: now}
		return true
	}

	// refill for the time since we last looked, capped at the bucket's size
	b.tokens += now.Sub(b.seen).Seconds() * l.rate
	if b.tokens > l.burst {
		b.tokens = l.burst
	}
	b.seen = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

func (l *Limiter) sweep(idleTTL time.Duration) {
	for range time.Tick(idleTTL) {
		cutoff := time.Now().Add(-idleTTL)

		l.mu.Lock()
		for client, b := range l.buckets {
			if b.seen.Before(cutoff) {
				delete(l.buckets, client)
			}
		}
		l.mu.Unlock()
	}
}

// Keyed buckets by `identity` instead of by network address.
//
// **an address is the wrong unit for anything a signed-in user does**: uzbek operators put thousands of
// subscribers behind one, and the failure is invisible in testing, where a laptop has an address to
// itself. main.go passes the caller's account id.
func (l *Limiter) Keyed(identity func(*http.Request) string) *Limiter {
	l.identity = identity
	return l
}

// who this request counts against
func (l *Limiter) client(r *http.Request) string {
	if l.identity != nil {
		return l.identity(r)
	}
	return ClientIP(r)
}

// Wrap puts the limiter in front of a handler. 429 plus a Retry-After, which is what tells an honest
// client with a buggy retry loop to back off rather than hammer harder.
func (l *Limiter) Wrap(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !l.Allow(l.client(r)) {
			Refuse(w, l.RetryAfter())
			return
		}
		next(w, r)
	}
}

// Refuse writes the one 429 every bucket answers with, so the app reads a single code whichever
// bucket said no - including one checked deeper than a handler, like geo's pace on yandex calls.
func Refuse(w http.ResponseWriter, retryAfter time.Duration) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter/time.Second)))
	w.WriteHeader(http.StatusTooManyRequests)
	json.NewEncoder(w).Encode(map[string]string{
		"code":  "rate_limited",
		"error": "too many requests, slow down",
	})
}

// RetryAfter is how long a refused caller waits for one token at the sustained rate, in whole
// seconds and never zero: a refused bucket holds less than one token, so this is never too early,
// and "retry in 0" is an immediate retry.
func (l *Limiter) RetryAfter() time.Duration {
	if l.rate <= 0 {
		// a bucket that never refills - only the tests build one
		return time.Hour
	}
	return time.Duration(math.Ceil(1/l.rate)) * time.Second
}

// EnvTrustProxy says whether a proxy writes the caller into X-Forwarded-For. it also makes main.go
// listen on loopback only, so nothing can reach the api around the proxy.
const EnvTrustProxy = "TRUST_PROXY"

func TrustProxy() bool {
	on, _ := TrustProxySetting()
	return on
}

// TrustProxySetting is EnvTrustProxy as written, and an error for anything that is not a boolean -
// **unset included, because a wrong guess is silent**: false behind nginx puts every caller in the
// country in 127.0.0.1's bucket, and a lenient read would turn a typo such as "yes" into that false.
func TrustProxySetting() (bool, error) {
	raw := strings.TrimSpace(os.Getenv(EnvTrustProxy))
	on, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("%s=%q: write true behind nginx or ngrok, false when phones reach this process directly", EnvTrustProxy, raw)
	}
	return on, nil
}

// ClientIP is the caller's network address. behind a proxy it is the **last** X-Forwarded-For entry: the
// proxy appends what it saw, so anything before it was written by the caller and reading the first one
// hands anybody a fresh bucket per request. without TRUST_PROXY the header is ignored.
func ClientIP(r *http.Request) string {
	if TrustProxy() {
		// Values, not Get: a header sent twice arrives as two values and the proxy's is the last
		if values := r.Header.Values("X-Forwarded-For"); len(values) > 0 {
			last := values[len(values)-1]
			if i := strings.LastIndexByte(last, ','); i >= 0 {
				last = last[i+1:]
			}
			if ip := strings.TrimSpace(last); ip != "" {
				return ip
			}
		}
	}

	// RemoteAddr is "ip:port", and the port changes every connection - bucketing by it limits nothing
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}
