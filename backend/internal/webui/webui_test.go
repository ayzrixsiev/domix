package webui

import (
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"testing"
)

// **An unsubstituted `{{SUPPORT_EMAIL}}` is a published legal document with a template tag in it**,
// and nothing else would notice: Page substitutes at startup, so a typo in a key renders silently
// and forever. Both pages are checked, because the next one added will be copied from one of them.
func TestNoTemplateTagSurvivesRendering(t *testing.T) {
	pages := map[string]map[string]string{
		"privacy.html":        {"SUPPORT_EMAIL": "test@example.com", "POLICY_VERSION": "2026-01-01"},
		"delete-account.html": {"SUPPORT_EMAIL": "test@example.com"},
	}

	leftover := regexp.MustCompile(`{{[A-Z_]+}}`)
	for name, vars := range pages {
		t.Run(name, func(t *testing.T) {
			body := render(t, name, vars)

			if tag := leftover.FindString(body); tag != "" {
				t.Fatalf("%s rendered with %s still in it", name, tag)
			}
			for key, value := range vars {
				if !strings.Contains(body, value) {
					t.Fatalf("%s does not contain the value substituted for %s", name, key)
				}
			}
		})
	}
}

// Both languages are in the markup and css picks one off <html lang>, which is what makes the page
// correct with javascript disabled. A reviewer following the url from the Play Console is the
// audience, and a blank page is a rejection.
func TestThePolicyRendersBothLanguagesWithoutJavascript(t *testing.T) {
	body := render(t, "privacy.html", map[string]string{
		"SUPPORT_EMAIL": "test@example.com", "POLICY_VERSION": "2026-01-01",
	})

	for _, want := range []string{`data-lang="ru"`, `data-lang="uz"`, `html[lang="ru"]`} {
		if !strings.Contains(body, want) {
			t.Fatalf("the policy page has no %s", want)
		}
	}
	// the deletion route is how a reader gets from the policy to acting on §7
	if !strings.Contains(body, `href="/delete-account"`) {
		t.Fatal("the policy page does not link to the deletion page")
	}
}

// **The policy exists twice - this page and privacy_policy.dart - and they are one document.** Two
// copies dated differently read as two different policies, which is exactly the mismatch between
// the app and its published policy that Google looks for. This is the only thing holding them
// together, since no build step generates one from the other.
func TestThePageAndTheAppAgreeOnThePolicyVersion(t *testing.T) {
	const dartFile = "../../../frontend/lib/features/onboarding/data/privacy_policy.dart"

	source, err := os.ReadFile(dartFile)
	if err != nil {
		// the backend is buildable on its own; this check only exists where the whole repo is
		t.Skipf("no app source next to the api: %v", err)
	}

	match := regexp.MustCompile(`policyVersion = '([^']+)'`).FindSubmatch(source)
	if match == nil {
		t.Fatal("privacy_policy.dart no longer declares policyVersion - this guard is now blind")
	}
	inApp := string(match[1])

	body := render(t, "privacy.html", map[string]string{
		"SUPPORT_EMAIL": "test@example.com", "POLICY_VERSION": inApp,
	})
	if !strings.Contains(body, inApp) {
		t.Fatalf("the app's policy is dated %s and the page does not carry that date", inApp)
	}
}

func render(t *testing.T, name string, vars map[string]string) string {
	t.Helper()

	rec := httptest.NewRecorder()
	Page(name, vars)(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("%s answered %d, want 200", name, rec.Code)
	}
	return rec.Body.String()
}
