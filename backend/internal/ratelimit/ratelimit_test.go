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
	if got := clientIP(requestFrom("203.0.113.7:51000", "198.51.100.1")); got != "203.0.113.7" {
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
		if got := clientIP(r); got != "203.0.113.7" {
			t.Errorf("%s: want 203.0.113.7, got %q", name, got)
		}
	}
}

func TestBehindAProxyWithNoHeaderTheSocketAddressIsUsed(t *testing.T) {
	t.Setenv("TRUST_PROXY", "true")

	if got := clientIP(requestFrom("127.0.0.1:40000")); got != "127.0.0.1" {
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
