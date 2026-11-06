package webui

import (
	"html"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"testing"
)

// the address the app's copy of the policy prints - see TestTheAppCarriesThePublishedPolicy
const appEmail = "domix.support@gmail.com"

func testSite(t *testing.T) *Site {
	t.Helper()
	s, err := NewSite(SiteConfig{SupportEmail: appEmail, PolicyVersion: "2026-10-08", TermsVersion: "2026-10-08"})
	if err != nil {
		t.Fatalf("NewSite: %v", err)
	}
	return s
}

func render(t *testing.T, h http.HandlerFunc) string {
	t.Helper()
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("answered %d, want 200", rec.Code)
	}
	return rec.Body.String()
}

// Every page is complete in all three languages, and nothing a template meant to fill is left
// showing. A stray `{{` on a published legal page is the kind of thing nobody notices for months.
func TestEveryPageRendersInAllThreeLanguages(t *testing.T) {
	s := testSite(t)
	for _, p := range sitePages {
		t.Run(p.key, func(t *testing.T) {
			body := render(t, s.Page(p.key))

			// `}}` alone is legal css (`@keyframes`), so only an opening pair means a missed action
			if strings.Contains(body, "{{") {
				t.Fatal("a template action survived rendering")
			}
			for _, lang := range []string{"ru", "uz", "en"} {
				if !strings.Contains(body, `data-lang="`+lang+`"`) {
					t.Fatalf("no %s text on the page", lang)
				}
			}
			// the css that makes the page read correctly with javascript off
			if !strings.Contains(body, `html[lang="en"] [data-lang="en"]`) {
				t.Fatal("the language rule is missing")
			}
		})
	}
}

// The deletion form has no business in search results; the documents should be findable.
func TestOnlyTheDeletionPageIsHiddenFromSearch(t *testing.T) {
	s := testSite(t)
	for _, p := range sitePages {
		hidden := strings.Contains(render(t, s.Page(p.key)), `name="robots" content="noindex"`)
		if hidden != (p.key == "delete-account") {
			t.Fatalf("%s: noindex = %v", p.key, hidden)
		}
	}
}

// The header marks the page being read, and only that one.
func TestTheNavMarksTheCurrentPage(t *testing.T) {
	s := testSite(t)
	current := regexp.MustCompile(`<a [^>]*aria-current="page"`)
	for _, p := range sitePages {
		if got := len(current.FindAllString(render(t, s.Page(p.key)), -1)); got != 1 {
			t.Fatalf("%s marks %d nav items as current, want 1", p.key, got)
		}
	}
}

func TestDatesAreWrittenTheWayEachLanguageSaysThem(t *testing.T) {
	cases := map[string]string{"ru": "8 октября 2026 г.", "uz": "2026-yil 8-oktabr", "en": "October 8, 2026"}
	for lang, want := range cases {
		got, err := humanDate(lang, "2026-10-08")
		if err != nil || got != want {
			t.Fatalf("%s: got %q, %v; want %q", lang, got, err, want)
		}
	}
	// a policy without its revision date cannot be cited, so this has to stop the boot
	if _, err := NewSite(SiteConfig{SupportEmail: appEmail, PolicyVersion: "08.10.2026", TermsVersion: "2026-10-08"}); err == nil {
		t.Fatal("a malformed policy date rendered")
	}
}

// ── the policy exists twice ──

// **The app carries the ru and uz policy as data and the site publishes the same text.** They are
// one document: if the app showed one policy and the published URL another, the user consented to
// something nobody can point at, and the Play listing would link to a third. No build step makes
// one from the other, so this is what holds them together - heading by heading, line by line.
func TestTheAppCarriesThePublishedPolicy(t *testing.T) {
	const dartFile = "../../../frontend/lib/features/onboarding/data/privacy_policy.dart"
	source, err := os.ReadFile(dartFile)
	if err != nil {
		// the backend builds on its own; this check only exists where the whole repo is
		t.Skipf("no app source next to the api: %v", err)
	}
	dart := string(source)
	page := render(t, testSite(t).Page("privacy"))

	version := regexp.MustCompile(`policyVersion = '([^']+)'`).FindStringSubmatch(dart)
	if version == nil || version[1] != "2026-11-06" {
		t.Fatalf("the app's policyVersion is %v, the site's is 2026-11-06 - move both", version)
	}

	for lang, names := range map[string][2]string{"ru": {"_leadRu", "_russian"}, "uz": {"_leadUz", "_uzbek"}} {
		t.Run(lang, func(t *testing.T) {
			want := pagePolicy(t, page, lang)
			got := dartPolicy(t, dart, names[0], names[1])

			if len(got) != len(want) {
				t.Fatalf("the app has %d lines, the site %d", len(got), len(want))
			}
			for i := range want {
				if got[i] != want[i] {
					t.Fatalf("line %d differs\n  app:  %q\n  site: %q", i+1, got[i], want[i])
				}
			}
		})
	}
}

var (
	tagRe   = regexp.MustCompile(`<[^>]+>`)
	blockRe = regexp.MustCompile(`(?s)<(h2|p|li)(?: class="lede")?>(.*?)</(?:h2|p|li)>`)
)

// the policy on the page as the app would hold it: the lede, then each heading and its lines in
// order, a bullet written the way the app writes one
func pagePolicy(t *testing.T, page, lang string) []string {
	t.Helper()
	article := regexp.MustCompile(`(?s)<article class="card doc" data-lang="` + lang + `">(.*?)</article>`).FindStringSubmatch(page)
	if article == nil {
		t.Fatalf("no %s article on the policy page", lang)
	}
	var lines []string
	for _, m := range blockRe.FindAllStringSubmatch(article[1], -1) {
		if strings.Contains(m[0], `class="meta"`) {
			continue
		}
		text := html.UnescapeString(tagRe.ReplaceAllString(m[2], ""))
		if m[1] == "li" {
			text = "• " + text
		}
		lines = append(lines, text)
	}
	return lines
}

// the same out of the dart source: string literals, adjacent ones joined the way dart joins them
func dartPolicy(t *testing.T, dart, lead, list string) []string {
	t.Helper()

	leadSrc := between(t, dart, "const String "+lead+" =", ";\n")
	lines := dartItems(leadSrc)

	body := between(t, dart, "const List<PolicySection> "+list+" = [", "\n];")
	for _, section := range strings.Split(body, "PolicySection(")[1:] {
		head, rest, ok := strings.Cut(section, "body:")
		if !ok {
			t.Fatalf("a section of %s has no body", list)
		}
		lines = append(lines, dartItems(head)...)
		lines = append(lines, dartItems(rest)...)
	}
	return lines
}

func between(t *testing.T, s, from, to string) string {
	t.Helper()
	_, after, ok := strings.Cut(s, from)
	if !ok {
		t.Fatalf("privacy_policy.dart has no %q - this guard is now blind", from)
	}
	inside, _, ok := strings.Cut(after, to)
	if !ok {
		t.Fatalf("privacy_policy.dart: %q is not closed", from)
	}
	return inside
}

// every dart string in src, adjacent literals joined into one. only double quotes, which is what
// the generated file uses; escapes are the three dart needs here
func dartItems(src string) []string {
	var items []string
	joinNext := false
	for i := 0; i < len(src); i++ {
		switch src[i] {
		case ',':
			joinNext = false
		case '"':
			var b strings.Builder
			for i++; i < len(src) && src[i] != '"'; i++ {
				if src[i] == '\\' && i+1 < len(src) {
					i++
				}
				b.WriteByte(src[i])
			}
			if joinNext {
				items[len(items)-1] += b.String()
			} else {
				items = append(items, b.String())
			}
			joinNext = true
		}
	}
	return items
}
