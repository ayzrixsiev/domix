// package webui serves the two web pages Domix has: the public account-deletion page Google Play
// requires, and the admin panel.
//
// the files are compiled into the binary with go:embed rather than read off disk like the product
// photos are, and the difference is deliberate. photos are content - they change without the code
// changing, there are hundreds of megabytes of them, and they live outside backend/ where embed
// cannot reach (§8). these two pages are part of the program: they are small, they change only when
// the code they talk to changes, and embedding them means deploying the api is copying one file.
// it also removes a whole failure mode - a page cannot 404 because a directory was not copied to
// the server.
//
// the cost is that editing a page needs a rebuild. `go run ./cmd/api` already restarts on every
// change, so in practice that is the same loop as before.
package webui

import (
	"embed"
	"net/http"
	"strings"
)

//go:embed pages/*.html
var pages embed.FS

// Page serves one embedded html file at an exact path, with `vars` substituted into it once at
// startup rather than on every request.
//
// substitution exists for one value - the support address on the deletion page - and it is done
// this way so that address is configuration rather than markup. it is the thing most likely to be
// wrong on somebody else's deployment, and the alternative is a founder editing html and
// rebuilding to change an email.
//
// an exact-match check rather than a file server, because http.HandleFunc("/admin", ...) in go's
// mux matches only "/admin" but a pattern ending in "/" would match every path beneath it - and a
// page that answers on /admin/anything invites someone to think those are routes.
func Page(name string, vars map[string]string) http.HandlerFunc {
	raw, err := pages.ReadFile("pages/" + name)
	if err != nil {
		// a missing file here is a build mistake, not a runtime condition: the embed directive
		// above would have failed to compile if the file were absent, so the only way to reach this
		// is a typo in a caller's name. answering 500 forever is the honest response.
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
		// no caching, unlike the product photos. a photo never changes under a given number, so it
		// is immutable for a year; these pages change with every deploy and a cached admin panel
		// talking to a newer api is a bug that only reproduces for whoever has the stale copy.
		w.Header().Set("Cache-Control", "no-cache")
		// this page is not meant to be framed by anyone. the deletion page because a play reviewer
		// following the url must see the real thing, and the admin panel because clickjacking a
		// "delete user" button is exactly the attack a frame buster exists for.
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")

		if r.Method == http.MethodHead {
			return
		}
		w.Write(rendered)
	}
}

// Redirect answers one alias path by sending the browser to the canonical one, so a url written
// down somewhere with a trailing slash or an older spelling still lands.
//
// this matters most for the deletion page: its url goes into the play console listing and into
// support replies, and those copies cannot be corrected once they are out.
func Redirect(to string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		target := to
		if q := r.URL.RawQuery; q != "" {
			target += "?" + q
		}
		http.Redirect(w, r, target, http.StatusMovedPermanently)
	}
}

// PathSuffix pulls the last segment off a request path, e.g. "/api/admin/users/42" -> "42".
// used by the admin routes, which mux patterns cannot destructure on this go version's http.ServeMux
// wildcard alone when the same handler serves several shapes.
func PathSuffix(path string) string {
	path = strings.TrimSuffix(path, "/")
	if i := strings.LastIndex(path, "/"); i >= 0 {
		return path[i+1:]
	}
	return path
}
