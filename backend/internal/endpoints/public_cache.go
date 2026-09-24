package endpoints

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"domix/backend/internal/dbctx"
)

// publicCache holds the answer to a read whose bytes are the same for everybody.
//
// **the home screen, the map and a category listing do not depend on who is asking**, and they are
// exactly what a crowd opens at once. without this, a thousand people opening the app is five
// thousand queries against a pool of ten connections. with it, it is one set of queries per [ttl]
// however many people arrive - which is also what lets the per-address limit in front of those
// routes be a floor against a flood rather than fine control, since there is no per-caller cost
// left to meter (CLAUDE.md §4).
//
// **per-shop reads are deliberately not in here.** an owner typing a price into their own catalogue
// has to see it on the next screen, and a crowd spreads across shops rather than piling onto one
// answer - so those stay one indexed read each.
//
// the nil cache builds every time, which is what the tests construct.
type publicCache struct {
	ttl time.Duration

	// how far past the ttl a copy may still be served when the rebuild itself fails. **this is what
	// keeps a database blip from emptying the home screen**: the alternative is answering 500 to
	// everybody while a perfectly good twenty-second-old copy sits in memory. bounded, because past
	// a few minutes "the app is showing something" stops being better than "the app says it failed".
	staleFor time.Duration

	mu      sync.Mutex
	entries map[string]*cachedAnswer
}

// one key's answer, with a lock of its own so a slow category cannot hold up the rest
type cachedAnswer struct {
	mu        sync.Mutex
	body      []byte
	writtenAt time.Time
}

// NewPublicCache is called once, in main.go, and handed to the endpoints that share it.
func NewPublicCache(ttl time.Duration) *publicCache {
	return &publicCache{ttl: ttl, staleFor: 5 * time.Minute, entries: make(map[string]*cachedAnswer)}
}

// serve answers from memory while the last copy is still fresh, and otherwise builds one - **once**.
// callers arriving during a rebuild wait for that answer rather than starting their own, which is
// the difference between a cache and a stampede on the moment it expires.
//
// `what` names the thing for the log line and for the error the app shows.
func (c *publicCache) serve(w http.ResponseWriter, r *http.Request, key, what string, build func(context.Context) (any, error)) {
	body, ok := c.body(w, r, key, what, build)
	if !ok {
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write(body)
}

func (c *publicCache) body(w http.ResponseWriter, r *http.Request, key, what string, build func(context.Context) (any, error)) ([]byte, bool) {
	if c == nil {
		body, err := buildBody(r, build)
		if err != nil {
			return nil, failedToLoad(w, r, what, err)
		}
		return body, true
	}

	entry := c.entryFor(key)

	// released before the body is written, so a slow phone downloading last second's answer cannot
	// hold up the next rebuild
	entry.mu.Lock()
	defer entry.mu.Unlock()

	age := time.Since(entry.writtenAt)
	if entry.body != nil && age < c.ttl {
		return entry.body, true
	}

	body, err := buildBody(r, build)
	if err != nil {
		// the copy we already hold, rather than an error, while it is still worth showing
		if entry.body != nil && age < c.ttl+c.staleFor {
			log.Printf("WARNING: serving %s from a %s-old copy - the rebuild failed: %v", what, age.Round(time.Second), err)
			return entry.body, true
		}
		// nothing is cached either way: the next caller asks the database again rather than being
		// handed this error for the rest of the ttl
		return nil, failedToLoad(w, r, what, err)
	}

	entry.body, entry.writtenAt = body, time.Now()
	return body, true
}

func (c *publicCache) entryFor(key string) *cachedAnswer {
	c.mu.Lock()
	defer c.mu.Unlock()

	entry, known := c.entries[key]
	if !known {
		// the key space is fixed - two endpoints and the twelve product categories, all validated
		// before they reach here - so this map never needs sweeping
		entry = &cachedAnswer{}
		c.entries[key] = entry
	}
	return entry
}

// builds one answer and encodes it.
//
// **the build gets a context of its own rather than the request's.** the answer belongs to everybody
// waiting on it, so the first caller hanging up must not cancel it for the rest.
func buildBody(r *http.Request, build func(context.Context) (any, error)) ([]byte, error) {
	ctx, cancel := dbctx.WithTimeout(context.WithoutCancel(r.Context()))
	defer cancel()

	payload, err := build(ctx)
	if err != nil {
		return nil, err
	}
	return json.Marshal(payload)
}

// always reports false, so callers can `return nil, failedToLoad(...)`
func failedToLoad(w http.ResponseWriter, r *http.Request, what string, err error) bool {
	if callerGone(r) {
		return false
	}
	log.Printf("CRITICAL: failed to load %s: %v", what, err)
	writeAPIError(w, http.StatusInternalServerError, "server_error", "failed to load "+what)
	return false
}
