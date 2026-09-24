// package webui serves Domix's two web pages: the account-deletion page Google Play requires, and
// the admin panel.
//
// embedded rather than read off disk like the photos are, because these are part of the program -
// they change only when the code they talk to changes, and embedding means deploying is copying one
// file and a page cannot 404 because a directory was not copied to the server.
package webui

import (
	"embed"
	"net/http"
	"strings"
)

//go:embed pages/*.html
var pages embed.FS

// serves one embedded html file, with `vars` substituted once at startup rather than per request.
// substitution exists for the support address on the deletion page, so it is configuration rather
// than markup.
func Page(name string, vars map[string]string) http.HandlerFunc {
	raw, err := pages.ReadFile("pages/" + name)
	if err != nil {
		// a build mistake, not a runtime condition: go:embed would not have compiled without the
		// file, so the only way here is a typo in a caller's name
		return func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "page not found", http.StatusInternalServerError)
		}
	}

	body := string(raw)
	for key, value := range vars {
		body = strings.ReplaceAll(body, "{{"+key+"}}", value)
	}
	rendered := []byte(body)

	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// no caching, unlike the photos: a cached admin panel talking to a newer api is a bug that
		// only reproduces for whoever holds the stale copy
		w.Header().Set("Cache-Control", "no-cache")
		// neither page is meant to be framed: clickjacking a "delete user" button is exactly the
		// attack a frame buster exists for
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")

		if r.Method == http.MethodHead {
			return
		}
		w.Write(rendered)
	}
}

// answers an alias path with the canonical one. it matters most for the deletion page, whose url
// goes into the Play Console listing and into support replies - copies that cannot be corrected.
func Redirect(to string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		target := to
		if q := r.URL.RawQuery; q != "" {
			target += "?" + q
		}
		http.Redirect(w, r, target, http.StatusMovedPermanently)
	}
}

// the last segment of a request path, e.g. "/api/admin/users/42" -> "42"
func PathSuffix(path string) string {
	path = strings.TrimSuffix(path, "/")
	if i := strings.LastIndex(path, "/"); i >= 0 {
		return path[i+1:]
	}
	return path
}
