package dbctx

import (
	"context"
	"time"
)

// how long any single database call may run before its context is cancelled (meaning: stop what you are doing) - this is what stops a
// stuck query (lock contention, a network blip, postgres hanging) from holding a pool connection
// forever, which would otherwise slowly starve every other request of connections too
const QueryTimeout = 5 * time.Second

// every incoming http request has it's own ctx, we pass it here as a parent
// after that we create our own child ctx which inherits from parent and adds it's own 5 seconds timer
// now we have return new ctx which watches for any connection issues and has 5 second timer
func WithTimeout(parent context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, QueryTimeout)
}
