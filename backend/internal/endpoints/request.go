package endpoints

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
)

// maxRequestBody caps how much of a request body we are willing to read.
//
// without it, `json.NewDecoder(r.Body).Decode(...)` reads until the client stops sending. that is
// not a theoretical problem: an attacker (or a bug in a retry loop) posting an endless body makes
// the server allocate until it dies, and it costs them almost nothing to do it. every json body this
// api takes is a handful of short fields, so 64 KiB is roughly a thousand times more than any honest
// request needs.
//
// nothing here is multipart any more - the excel upload was the one endpoint that took a large body,
// and it is gone (migration 000006) - so one limit covers the whole api.
const maxRequestBody = 64 << 10 // 64 KiB

// decodeJSONBody reads and validates one json request body, writing the 400 itself on failure.
// callers just `return` when it reports false.
//
// this was copy-pasted into six handlers, each with its own slightly different error text and none
// of them capping the read. one helper means the limit cannot be forgotten on the seventh.
func decodeJSONBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	// MaxBytesReader wraps the body so reads past the limit fail, *and* tells the server to close
	// the connection rather than keep draining a client that is still sending. r.Body is replaced
	// rather than shadowed so the decoder below cannot accidentally read the unwrapped original.
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBody)

	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		// a body that was too large is a different mistake from a body that was malformed, and the
		// app can only tell them apart if we say so. MaxBytesError is the typed error the wrapper
		// above returns once the limit is passed.
		//
		// errors.AsType is the go 1.26 generic form of errors.As: it returns the unwrapped error of
		// the requested type plus an ok flag, instead of taking a pointer to a variable to fill in.
		// the `_` is that error value - we only need to know that this *is* the too-large case, not
		// what limit it reports, since we set the limit ourselves two lines up.
		if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
			writeAPIError(w, http.StatusRequestEntityTooLarge, "body_too_large",
				fmt.Sprintf("request body exceeds %d bytes", maxRequestBody))
			return false
		}
		writeAPIError(w, http.StatusBadRequest, "invalid_body", "invalid json body")
		return false
	}

	return true
}

// validateCoordinates rejects a latitude/longitude pair that cannot be a real place.
//
// PostGIS stores whatever it is handed: ST_MakePoint(999, 999) is a perfectly valid geometry as far
// as the database is concerned, it is simply nowhere. the shop would be written successfully and
// then never appear on the map, with nothing in any log to say why - the worst kind of failure,
// because it looks like it worked.
func validateCoordinates(latitude, longitude float64) *accessError {
	if latitude < -90 || latitude > 90 {
		return &accessError{http.StatusBadRequest, "invalid_location", "latitude must be between -90 and 90"}
	}
	if longitude < -180 || longitude > 180 {
		return &accessError{http.StatusBadRequest, "invalid_location", "longitude must be between -180 and 180"}
	}

	// exactly (0, 0) is a real point in the Gulf of Guinea and a shop will never be there. what it
	// actually means is a form that submitted before a location was picked, since 0 is the zero
	// value of a float64 - so this catches a client bug that would otherwise silently produce a
	// shop pinned to Null Island.
	if latitude == 0 && longitude == 0 {
		return &accessError{http.StatusBadRequest, "invalid_location", "a location must be picked on the map"}
	}

	return nil
}

// callerGone: the phone hung up before we could answer, which cancels the query with it. not an
// incident - logged as CRITICAL it would bury the real ones on a flaky network or under a load test.
func callerGone(r *http.Request) bool {
	return r.Context().Err() != nil
}
