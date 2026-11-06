package geo

import (
	"context"
	"log"
	"sync"
	"time"
)

// cache is endpoints.publicCache's pattern over keys the caller types: one fetch per key while the
// others wait on it, a fetch that outlives the caller who started it, and the last copy served while
// yandex cannot answer.
//
// **an entry exists only for an answer yandex gave**, and each one cost a unit of a daily budget, so the
// map cannot grow past a week of that budget no matter what is typed. a failed fetch leaves nothing.
//
// **nothing here may depend on who is asking**: the key is the query and the language, and one caller's
// answer is everybody's.
type cache[T any] struct {
	ttl, staleFor time.Duration

	mu      sync.Mutex
	entries map[string]*cacheEntry[T]
}

type cacheEntry[T any] struct {
	mu        sync.Mutex
	value     T
	held      bool
	writtenAt time.Time
}

func newCache[T any](ttl, staleFor time.Duration) *cache[T] {
	c := &cache[T]{ttl: ttl, staleFor: staleFor, entries: make(map[string]*cacheEntry[T])}
	go c.sweep(time.Hour)
	return c
}

func (c *cache[T]) get(ctx context.Context, key string, fetch func(context.Context) (T, error)) (T, error) {
	entry := c.entryFor(key)
	entry.mu.Lock()
	defer entry.mu.Unlock()

	age := time.Since(entry.writtenAt)
	if entry.held && age < c.ttl {
		return entry.value, nil
	}

	// its own context: the answer belongs to everybody waiting on this key, so the first caller hanging up
	// must not cancel it for the rest, and a call already paid for should land in the cache
	fetchCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), fetchTimeout)
	defer cancel()

	value, err := fetch(fetchCtx)
	if err != nil {
		if entry.held && age < c.ttl+c.staleFor {
			log.Printf("WARNING: answering %q from a %s-old copy - %v", key, age.Round(time.Minute), err)
			return entry.value, nil
		}
		if !entry.held {
			c.forget(key, entry)
		}
		var zero T
		return zero, err
	}

	entry.value, entry.held, entry.writtenAt = value, true, time.Now()
	return value, nil
}

func (c *cache[T]) entryFor(key string) *cacheEntry[T] {
	c.mu.Lock()
	defer c.mu.Unlock()

	entry, known := c.entries[key]
	if !known {
		entry = &cacheEntry[T]{}
		c.entries[key] = entry
	}
	return entry
}

// only this entry: a caller that arrived meanwhile may already have put a fresh one under the key
func (c *cache[T]) forget(key string, entry *cacheEntry[T]) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.entries[key] == entry {
		delete(c.entries, key)
	}
}

func (c *cache[T]) sweep(every time.Duration) {
	for range time.Tick(every) {
		c.mu.Lock()
		for key, entry := range c.entries {
			// a locked entry is mid-fetch, and is looked at again next hour
			if !entry.mu.TryLock() {
				continue
			}
			if entry.held && time.Since(entry.writtenAt) > c.ttl+c.staleFor {
				delete(c.entries, key)
			}
			entry.mu.Unlock()
		}
		c.mu.Unlock()
	}
}
