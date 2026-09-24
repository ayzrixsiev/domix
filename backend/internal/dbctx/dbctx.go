package dbctx

import (
	"context"
	"time"
)

// how long any single database call may run. this is what stops a stuck query - lock contention, a
// network blip, postgres hanging - from holding a pool connection forever and starving every other
// request of connections behind it.
const QueryTimeout = 5 * time.Second

// a child of the request's own context, so it carries both the caller hanging up and this deadline
func WithTimeout(parent context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, QueryTimeout)
}
