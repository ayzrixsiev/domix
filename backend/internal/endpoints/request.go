package endpoints

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
)

// how much of a request body we are willing to read. without it a decoder reads until the client
// stops sending, which is an allocation loop anybody can start. every json body here is a handful
// of short fields; the one multipart endpoint has its own limit (imagestore.MaxUploadBytes).
const maxRequestBody = 64 << 10 // 64 KiB

// decodeJSONBody reads one json request body, writing the 400 itself on failure. callers just
// `return` when it reports false - one helper, so the size limit cannot be forgotten on a new route.
func decodeJSONBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	// r.Body is replaced rather than shadowed, so the decoder cannot read the unwrapped original
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBody)

	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		// too large and malformed are different mistakes, and the app shows a different message
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

// validateCoordinates rejects a pair that cannot be a real place. PostGIS stores whatever it is
// handed, so without this the shop is written successfully and then never appears on the map.
func validateCoordinates(latitude, longitude float64) *accessError {
	if latitude < -90 || latitude > 90 {
		return &accessError{http.StatusBadRequest, "invalid_location", "latitude must be between -90 and 90"}
	}
	if longitude < -180 || longitude > 180 {
		return &accessError{http.StatusBadRequest, "invalid_location", "longitude must be between -180 and 180"}
	}

	// (0, 0) means a form submitted before a location was picked - 0 is float64's zero value
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
