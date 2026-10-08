// package webui serves the html Domix answers with itself: the public site - home, privacy policy,
// terms of use, account deletion - and the admin panel.
//
// embedded rather than read off disk like the photos are, because these are part of the program -
// they change only when the code they talk to changes, and embedding means deploying is copying one
// file and a page cannot 404 because a directory was not copied to the server.
package webui

import (
	"bytes"
	"embed"
	"fmt"
	"html/template"
	"net/http"
	"strings"
	"time"
)

//go:embed pages/*.html
var pages embed.FS

//go:embed site/*.html
var site embed.FS

// Page serves one embedded file exactly as it is: the admin panel, an app of its own that shares
// nothing with the public site.
func Page(name string) http.HandlerFunc {
	raw, err := pages.ReadFile("pages/" + name)
	if err != nil {
		// a build mistake, not a runtime condition: go:embed would not have compiled without the
		// file, so the only way here is a typo in a caller's name
		return func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "page not found", http.StatusInternalServerError)
		}
	}
	return serve(raw)
}

// SiteConfig is what the public pages print that is configuration rather than copy.
type SiteConfig struct {
	SupportEmail string

	// ISO dates. the policy's has to match privacy_policy.dart's policyVersion - see the test
	PolicyVersion string
	TermsVersion  string
}

// Site is the public site: four pages inside one shell, so the header, the language switch and the
// footer are written once. **every page is rendered at startup**, which turns a broken template into
// a refusal to boot rather than a 500 for whoever opens the page first.
type Site struct {
	pages map[string][]byte
}

// the three languages of one string
type text struct{ Ru, Uz, En string }

type sitePage struct {
	key   string // the template file and the nav item
	title text

	// false keeps a page out of search results: a form that deletes accounts has no business there
	index bool
}

var sitePages = []sitePage{
	{key: "home", index: true, title: text{
		"Domix — строительные магазины на карте", "Domix — qurilish do‘konlari xaritada", "Domix — building supply stores on a map"}},
	{key: "privacy", index: true, title: text{
		"Политика конфиденциальности — Domix", "Maxfiylik siyosati — Domix", "Privacy Policy — Domix"}},
	{key: "terms", index: true, title: text{
		"Условия использования — Domix", "Foydalanish shartlari — Domix", "Terms of Use — Domix"}},
	{key: "delete-account", title: text{
		"Удаление аккаунта — Domix", "Akkauntni o‘chirish — Domix", "Delete your account — Domix"}},
}

// what every template sees
type pageData struct {
	Key   string
	Title text
	Index bool
	Year  int

	Email         string
	PolicyVersion string
	TermsVersion  string
}

func NewSite(cfg SiteConfig) (*Site, error) {
	funcs := template.FuncMap{"date": humanDate}
	s := &Site{pages: make(map[string][]byte, len(sitePages))}

	for _, p := range sitePages {
		tpl, err := template.New(p.key).Funcs(funcs).ParseFS(site, "site/layout.html", "site/"+p.key+".html")
		if err != nil {
			return nil, fmt.Errorf("webui: parsing %s: %w", p.key, err)
		}

		var out bytes.Buffer
		err = tpl.ExecuteTemplate(&out, "layout", pageData{
			Key:           p.key,
			Title:         p.title,
			Index:         p.index,
			Year:          time.Now().Year(),
			Email:         cfg.SupportEmail,
			PolicyVersion: cfg.PolicyVersion,
			TermsVersion:  cfg.TermsVersion,
		})
		if err != nil {
			return nil, fmt.Errorf("webui: rendering %s: %w", p.key, err)
		}
		s.pages[p.key] = out.Bytes()
	}
	return s, nil
}

// Page is one of the four, by key. an unknown key is a wiring mistake in main.go and panics there,
// at startup, rather than serving nothing quietly.
func (s *Site) Page(key string) http.HandlerFunc {
	body, ok := s.pages[key]
	if !ok {
		panic("webui: no site page " + key)
	}
	return serve(body)
}

func serve(body []byte) http.HandlerFunc {
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
		// none of these pages is meant to be framed: clickjacking a "delete" button is exactly the
		// attack a frame buster exists for
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")

		if r.Method == http.MethodHead {
			return
		}
		w.Write(body)
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

var months = map[string][12]string{
	"ru": {"января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"},
	"uz": {"yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr", "noyabr", "dekabr"},
	"en": {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"},
}

// humanDate writes an ISO date the way each language says it: «8 октября 2026 г.», «2026-yil
// 8-oktabr», «October 8, 2026». an unparseable date stops the boot through NewSite - a policy
// printed without its revision date is a policy nobody can cite.
func humanDate(lang, iso string) (string, error) {
	d, err := time.Parse(time.DateOnly, strings.TrimSpace(iso))
	if err != nil {
		return "", fmt.Errorf("webui: %q is not a YYYY-MM-DD date", iso)
	}
	names, ok := months[lang]
	if !ok {
		return "", fmt.Errorf("webui: no month names for %q", lang)
	}
	month := names[d.Month()-1]

	switch lang {
	case "ru":
		return fmt.Sprintf("%d %s %d г.", d.Day(), month, d.Year()), nil
	case "uz":
		return fmt.Sprintf("%d-yil %d-%s", d.Year(), d.Day(), month), nil
	default:
		return fmt.Sprintf("%s %d, %d", month, d.Day(), d.Year()), nil
	}
}
