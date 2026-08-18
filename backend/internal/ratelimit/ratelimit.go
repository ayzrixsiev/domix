// package ratelimit caps how fast one caller can hit the api.
//
// Nothing in this service limited anything before, which mattered most on the two endpoints that
// need no login at all. POST /api/auth/init stores a session in RAM for ten minutes per call, so an
// unthrottled loop is a memory-exhaustion button anyone can press; GET /api/auth/status is the
// lookup that hands out a JWT when you name a live session, so an unthrottled loop is also the only
// thing making a guessing attack expensive.
//
// **In-memory and per-process, which is a real limit on what this can promise.** Two instances
// behind a load balancer each enforce their own budget, so the effective rate doubles. That is the
// right trade at one server and stops being right the day there are two - at which point the limiter
// belongs in front of the app (nginx, Cloudflare) or in Redis, not here. It is a floor, not a
// perimeter.
package ratelimit

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// Limiter is a token bucket per client, refilled continuously.
//
// A bucket rather than a counter per fixed window, because a window resets on a wall-clock edge: a
// caller allowed 60/minute can send 60 at 11:59:59 and 60 more at 12:00:00, which is 120 in one
// second - exactly the burst the limit existed to prevent. A bucket holds at most Burst tokens and
// earns Rate of them per second, so a quiet client keeps a small allowance for a genuine spike and a
// loud one is held at Rate forever.
type Limiter struct {
	rate  float64 // tokens earned per second
	burst float64 // most tokens a bucket can hold

	mu      sync.Mutex
	buckets map[string]*bucket
}

type bucket struct {
	tokens float64
	seen   time.Time
}

// New builds a limiter allowing `rate` requests per second sustained, with room for `burst` in one
// go, and starts a sweeper that forgets clients idle for longer than `idleTTL`.
//
// The sweeper is what keeps the map from becoming the leak the limiter was meant to prevent: every
// distinct IP allocates an entry, and an attacker rotating source addresses would otherwise grow it
// without bound.
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

	// refill for the time that has passed since we last looked, capped at the bucket's size
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

// Wrap puts the limiter in front of a handler. A rejected caller gets 429 and a Retry-After, which
// is what tells an honest client (a retry loop with a bug) to back off rather than hammer harder.
func (l *Limiter) Wrap(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !l.Allow(clientIP(r)) {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Retry-After", "1")
			w.WriteHeader(http.StatusTooManyRequests)
			json.NewEncoder(w).Encode(map[string]string{
				"code":  "rate_limited",
				"error": "too many requests, slow down",
			})
			return
		}
		next(w, r)
	}
}

// clientIP identifies the caller to bucket them by.
//
// **X-Forwarded-For is only trusted when TRUST_PROXY is set, and that default is the safe one.** The
// header is written by the client unless something in front of the app overwrites it, so trusting it
// unconditionally hands every attacker an unlimited supply of identities - they change one string
// and get a fresh bucket per request, which is worse than having no limiter at all because it looks
// like there is one. Trusting it never, on the other hand, means that once this runs behind nginx or
// Cloudflare every request appears to come from the proxy and the whole internet shares one bucket.
//
// Both failure modes are silent, so the choice is explicit: set TRUST_PROXY=true *only* once there
// is a proxy in front that always rewrites the header.
func clientIP(r *http.Request) string {
	if os.Getenv("TRUST_PROXY") == "true" {
		if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
			// leftmost entry is the original client; the rest are the proxies it passed through
			if first, _, found := strings.Cut(forwarded, ","); found {
				return strings.TrimSpace(first)
			}
			return strings.TrimSpace(forwarded)
		}
	}

	// RemoteAddr is "ip:port"; the port changes every connection, so bucketing by it would give
	// every request its own bucket and limit nothing
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}
