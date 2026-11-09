package ratelimit

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// who the limiter thinks is calling: behind a proxy, the last X-Forwarded-For entry (the one the
// proxy wrote); otherwise the socket's own address, whatever the headers claim.

func requestFrom(remoteAddr string, forwardedFor ...string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/api/products/search?q=kabel", nil)
	r.RemoteAddr = remoteAddr
	for _, value := range forwardedFor {
		r.Header.Add("X-Forwarded-For", value)
	}
	return r
}

func TestWithoutTrustProxyTheHeaderIsIgnored(t *testing.T) {
	t.Setenv("TRUST_PROXY", "")

	// nothing sits in front, so the header can only have been written by the caller
	if got := ClientIP(requestFrom("203.0.113.7:51000", "198.51.100.1")); got != "203.0.113.7" {
		t.Fatalf("want the socket's own address, got %q", got)
	}
}

func TestBehindAProxyTheLastEntryIsTheCaller(t *testing.T) {
	t.Setenv("TRUST_PROXY", "true")

	cases := map[string]*http.Request{
		// the proxy appended the address it saw to what the caller sent
		"appended": requestFrom("127.0.0.1:40000", "6.6.6.6, 203.0.113.7"),
		// the same, arriving as two header lines rather than one comma-joined one
		"two header lines": requestFrom("127.0.0.1:40000", "6.6.6.6", "203.0.113.7"),
		// a caller who sent nothing: the proxy's entry is the only one
		"single": requestFrom("127.0.0.1:40000", "203.0.113.7"),
	}
	for name, r := range cases {
		if got := ClientIP(r); got != "203.0.113.7" {
			t.Errorf("%s: want 203.0.113.7, got %q", name, got)
		}
	}
}

func TestBehindAProxyWithNoHeaderTheSocketAddressIsUsed(t *testing.T) {
	t.Setenv("TRUST_PROXY", "true")

	if got := ClientIP(requestFrom("127.0.0.1:40000")); got != "127.0.0.1" {
		t.Fatalf("want 127.0.0.1, got %q", got)
	}
}

// the attack the first-entry rule allowed: a made-up address in front of every request.
func TestRotatingASpoofedAddressDoesNotBuyAFreshBucket(t *testing.T) {
	t.Setenv("TRUST_PROXY", "true")

	limiter := New(0.001, 2, time.Hour) // two requests, then effectively nothing
	handler := limiter.Wrap(func(w http.ResponseWriter, r *http.Request) {})

	codes := make([]int, 0, 3)
	for _, spoofed := range []string{"1.1.1.1", "2.2.2.2", "3.3.3.3"} {
		rec := httptest.NewRecorder()
		handler(rec, requestFrom("127.0.0.1:40000", spoofed+", 203.0.113.7"))
		codes = append(codes, rec.Code)
	}

	if codes[2] != http.StatusTooManyRequests {
		t.Fatalf("the third request should have been refused, got %v", codes)
	}
}

// **the bug this exists to catch is invisible on a laptop**: uzbek operators put thousands of subscribers
// behind one address, so bucketing an authenticated request by address throttles a whole carrier.
func TestKeyedBucketsByAccountRatherThanAddress(t *testing.T) {
	// one token, so the second request from the same bucket is refused
	limiter := New(0, 1, time.Minute).Keyed(func(r *http.Request) string {
		return "user:" + r.Header.Get("X-Test-Account")
	})

	var served int
	handler := limiter.Wrap(func(w http.ResponseWriter, r *http.Request) { served++ })

	// two different accounts, one shared address - the shape of a carrier NAT
	for _, account := range []string{"1", "2"} {
		req := requestFrom("203.0.113.7:51000")
		req.Header.Set("X-Test-Account", account)
		handler(httptest.NewRecorder(), req)
	}
	if served != 2 {
		t.Fatalf("%d of 2 accounts behind one address were served - they share a bucket", served)
	}

	// and the same account is still held to its own budget
	req := requestFrom("198.51.100.4:51000")
	req.Header.Set("X-Test-Account", "1")
	rec := httptest.NewRecorder()
	handler(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("a second request from one account answered %d, want 429", rec.Code)
	}
}

// **a Retry-After shorter than the refill invites the retry that will be refused**: the app-wide geo
// pace earns a token every twelve seconds, and a one-second answer tells a client to come back early.
func TestARefusalSaysWhenTheNextTokenArrives(t *testing.T) {
	cases := map[string]struct {
		limiter *Limiter
		want    string
	}{
		"twenty a second rounds up, never to zero": {New(20, 1, time.Minute), "1"},
		"three hundred an hour":                    {New(300.0/3600, 1, time.Minute), "12"},
		"one per ten minutes":                      {New(1.0/600, 1, time.Minute), "600"},
	}
	for name, c := range cases {
		handler := c.limiter.Wrap(func(w http.ResponseWriter, r *http.Request) {})
		handler(httptest.NewRecorder(), requestFrom("203.0.113.7:51000"))

		rec := httptest.NewRecorder()
		handler(rec, requestFrom("203.0.113.7:51000"))
		if rec.Code != http.StatusTooManyRequests {
			t.Fatalf("%s: the second request answered %d, want 429", name, rec.Code)
		}
		if got := rec.Header().Get("Retry-After"); got != c.want {
			t.Errorf("%s: Retry-After %q, want %q", name, got, c.want)
		}
	}
}

// **both wrong guesses are silent in production**, so neither an absent line nor a typo may boot
func TestTrustProxyMustBeWrittenAsABoolean(t *testing.T) {
	for _, raw := range []string{"", "yes", "on "} {
		t.Setenv(EnvTrustProxy, raw)
		if _, err := TrustProxySetting(); err == nil {
			t.Errorf("TRUST_PROXY=%q was accepted, want a refusal", raw)
		}
	}
	for raw, want := range map[string]bool{"true": true, " false ": false, "1": true} {
		t.Setenv(EnvTrustProxy, raw)
		if got, err := TrustProxySetting(); err != nil || got != want {
			t.Errorf("TRUST_PROXY=%q read as %v (%v), want %v", raw, got, err, want)
		}
	}
}
