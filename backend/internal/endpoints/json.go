package endpoints

import "net/http"

// wraps a handler so every json api response carries the right content type.
//
// this used to also send CORS headers (Access-Control-Allow-*), removed because nothing in this
// project ever needed them: the flutter app is a native client, not a browser, and every browser
// page this api serves (admin.html, delete-account.html) calls back into this same api with
// relative paths, which is same-origin and never triggers a browser's CORS check in the first
// place. add it back the day something genuinely cross-origin calls this api from a browser.
func WithJSON(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		next(w, r)
	}
}
