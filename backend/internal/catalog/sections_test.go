package catalog

import (
	"os"
	"regexp"
	"testing"
)

// a code the app does not know parses to no section, so its rows drop out of the «Категории» sheet
// while still being sent: nothing fails, the products are simply not under any heading
func TestTheAppAndTheApiAgreeOnSections(t *testing.T) {
	const dartFile = "../../../frontend/lib/features/products/data/product_section.dart"
	source, err := os.ReadFile(dartFile)
	if err != nil {
		t.Fatalf("read %s: %v", dartFile, err)
	}

	inApp := map[string]bool{}
	for _, match := range regexp.MustCompile(`(?m)^\s+\w+\('([a-z_]+)'\)[,;]$`).FindAllStringSubmatch(string(source), -1) {
		inApp[match[1]] = true
	}
	if len(inApp) == 0 {
		t.Fatalf("product_section.dart declares no sections - this guard is now blind")
	}

	for code := range sections {
		if !inApp[code] {
			t.Errorf("section %q is accepted by the api but has no ProductSection in the app", code)
		}
	}
	for code := range inApp {
		if !sections[code] {
			t.Errorf("ProductSection %q is unknown to the api, which would refuse a template row carrying it", code)
		}
	}
}
