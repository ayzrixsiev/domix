package endpoints

// publicCache is what stands between a crowd and the connection pool, so the properties worth
// pinning are the ones that stop being true quietly: one build for many callers, and a failure that
// does not stick around.

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func cacheRequest() *http.Request {
	return httptest.NewRequest(http.MethodGet, "/api/home", nil)
}

// **the point of the whole file.** a thousand phones opening the app at once must not be a thousand
// trips to the database - and the moment the entry expires is exactly when they would all miss at
// once, so "cached" is not enough: they have to wait for the one rebuild rather than start their own.
func TestOneBuildAnswersEveryCallerAtOnce(t *testing.T) {
	cache := NewPublicCache(time.Minute)

	var builds int
	var mu sync.Mutex

	var callers sync.WaitGroup
	for range 50 {
		callers.Add(1)
		go func() {
			defer callers.Done()
			cache.serve(httptest.NewRecorder(), cacheRequest(), "home", "home content",
				func(context.Context) (any, error) {
					mu.Lock()
					builds++
					mu.Unlock()
					// long enough that every other caller is certainly inside serve by now
					time.Sleep(20 * time.Millisecond)
					return map[string]int{"shops": 3}, nil
				})
		}()
	}
	callers.Wait()

	if builds != 1 {
		t.Fatalf("50 callers caused %d builds, want 1", builds)
	}
}

func TestAFreshAnswerIsServedFromMemoryAndAStaleOneIsRebuilt(t *testing.T) {
	cache := NewPublicCache(30 * time.Millisecond)

	builds := 0
	ask := func() string {
		rec := httptest.NewRecorder()
		cache.serve(rec, cacheRequest(), "home", "home content", func(context.Context) (any, error) {
			builds++
			return map[string]int{"build": builds}, nil
		})
		return rec.Body.String()
	}

	first := ask()
	if second := ask(); second != first {
		t.Fatalf("a second call inside the ttl answered %s, want the cached %s", second, first)
	}
	if builds != 1 {
		t.Fatalf("%d builds inside one ttl, want 1", builds)
	}

	time.Sleep(40 * time.Millisecond)
	if third := ask(); third == first {
		t.Fatalf("the answer was still %s after the ttl expired", third)
	}
}

// keys do not bleed into each other: twelve category listings share one cache
func TestEachKeyIsCachedOnItsOwn(t *testing.T) {
	cache := NewPublicCache(time.Minute)

	ask := func(key, value string) string {
		rec := httptest.NewRecorder()
		cache.serve(rec, cacheRequest(), key, "products", func(context.Context) (any, error) {
			return map[string]string{"category": value}, nil
		})
		return rec.Body.String()
	}

	mixes := ask("category:mixes", "mixes")
	if tools := ask("category:tools", "tools"); tools == mixes {
		t.Fatalf("two categories share one entry: both answered %s", tools)
	}
}

// **a failure must not be cached.** the database blinking for one request would otherwise hand the
// same 500 to everybody for the rest of the ttl, long after it had recovered.
func TestAFailureIsNotHeldOnTo(t *testing.T) {
	cache := NewPublicCache(time.Minute)

	failing := true
	ask := func() *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		cache.serve(rec, cacheRequest(), "home", "home content", func(context.Context) (any, error) {
			if failing {
				return nil, errors.New("database is having a moment")
			}
			return map[string]int{"shops": 3}, nil
		})
		return rec
	}

	if rec := ask(); rec.Code != http.StatusInternalServerError {
		t.Fatalf("a failed build answered %d, want 500", rec.Code)
	}

	failing = false
	if rec := ask(); rec.Code != http.StatusOK {
		t.Fatalf("the next call answered %d, want 200 - the failure was cached", rec.Code)
	}
}

// every endpoint test in this package builds its handler without a cache, so the nil one has to be
// a working passthrough rather than a panic
func TestTheNilCacheBuildsEveryTime(t *testing.T) {
	var cache *publicCache

	builds := 0
	for range 3 {
		rec := httptest.NewRecorder()
		cache.serve(rec, cacheRequest(), "home", "home content", func(context.Context) (any, error) {
			builds++
			return map[string]int{"shops": 1}, nil
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("answered %d, want 200", rec.Code)
		}
	}
	if builds != 3 {
		t.Fatalf("%d builds, want one per call", builds)
	}
}

// **a database blip must not empty the home screen.** the copy in memory is seconds old and
// perfectly good; answering 500 with it sitting right there is the failure mode this guards.
func TestAStaleCopyIsServedWhenTheRebuildFails(t *testing.T) {
	cache := NewPublicCache(20 * time.Millisecond)

	failing := false
	ask := func() *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		cache.serve(rec, cacheRequest(), "home", "home content", func(context.Context) (any, error) {
			if failing {
				return nil, errors.New("database is having a moment")
			}
			return map[string]int{"shops": 3}, nil
		})
		return rec
	}

	good := ask().Body.String()

	failing = true
	time.Sleep(30 * time.Millisecond) // past the ttl, so the next call rebuilds - and fails

	rec := ask()
	if rec.Code != http.StatusOK {
		t.Fatalf("answered %d while holding a usable copy, want 200", rec.Code)
	}
	if rec.Body.String() != good {
		t.Fatalf("answered %s, want the last good copy %s", rec.Body, good)
	}
}

// but not forever: past staleFor, "the app failed" is more honest than last week's prices
func TestAStaleCopyIsNotServedForever(t *testing.T) {
	cache := NewPublicCache(10 * time.Millisecond)
	cache.staleFor = 20 * time.Millisecond

	failing := false
	ask := func() *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		cache.serve(rec, cacheRequest(), "home", "home content", func(context.Context) (any, error) {
			if failing {
				return nil, errors.New("database is still down")
			}
			return map[string]int{"shops": 3}, nil
		})
		return rec
	}

	ask()
	failing = true
	time.Sleep(50 * time.Millisecond) // past ttl + staleFor

	if rec := ask(); rec.Code != http.StatusInternalServerError {
		t.Fatalf("answered %d on a copy too old to show, want 500", rec.Code)
	}
}

// **a failed rebuild is shared like a good one.** against a database that hangs, each caller behind it
// retrying in turn would wait five seconds per caller ahead of them - the last good copy reaching
// nobody before the app gave up on it.
func TestCallersQueuedBehindAFailedBuildShareItsResult(t *testing.T) {
	for name, held := range map[string]bool{"with a copy to fall back on": true, "with nothing held": false} {
		t.Run(name, func(t *testing.T) {
			cache := NewPublicCache(20 * time.Millisecond)
			if held {
				cache.serve(httptest.NewRecorder(), cacheRequest(), "home", "home content",
					func(context.Context) (any, error) { return map[string]int{"shops": 3}, nil })
				time.Sleep(30 * time.Millisecond) // past the ttl, so the next caller rebuilds
			}

			var builds atomic.Int32
			codes := make(chan int, 20)
			var callers sync.WaitGroup
			for range 20 {
				callers.Add(1)
				go func() {
					defer callers.Done()
					rec := httptest.NewRecorder()
					cache.serve(rec, cacheRequest(), "home", "home content", func(context.Context) (any, error) {
						builds.Add(1)
						// long enough that every other caller is queued on the key by the time this fails
						time.Sleep(100 * time.Millisecond)
						return nil, errors.New("database is hanging")
					})
					codes <- rec.Code
				}()
			}
			callers.Wait()
			close(codes)

			if builds.Load() != 1 {
				t.Fatalf("20 queued callers caused %d rebuilds, want 1", builds.Load())
			}
			want := http.StatusInternalServerError
			if held {
				want = http.StatusOK
			}
			for code := range codes {
				if code != want {
					t.Fatalf("a queued caller answered %d, want %d", code, want)
				}
			}
		})
	}
}
