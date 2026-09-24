package endpoints

import (
	"log"
	"net/http"
	"runtime/debug"
)

// wraps a handler so every json api response carries the right content type, and so a panic inside
// it becomes a logged 500 rather than a dropped connection. no CORS headers: the app is a native
// client and both web pages call this api same-origin.
//
// **net/http already stops a panic from killing the process, but it answers nothing**: it closes the
// connection, so the app sees a network failure it retries forever and the only record is a stack
// trace nobody correlated with a request. this turns it into an error the app can show.
func WithJSON(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		defer recoverInto(w, r)
		next(w, r)
	}
}

func recoverInto(w http.ResponseWriter, r *http.Request) {
	problem := recover()
	if problem == nil {
		return
	}
	log.Printf("CRITICAL: panic serving %s %s: %v\n%s", r.Method, r.URL.Path, problem, debug.Stack())

	// WriteHeader on a response that has already started is a no-op with a warning, which is the
	// right outcome: the handler panicked halfway through a body nobody can un-send.
	writeAPIError(w, http.StatusInternalServerError, "server_error", "something went wrong, try again")
}
