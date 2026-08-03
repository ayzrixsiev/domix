package catalog

import (
	"testing"
	"unicode/utf8"
)

// the templates are a hand-maintained list of 120 lines. the failure mode isn't a compile error,
// it's a shop owner opening their brand-new shop and finding 49 tiles, or two tiles with the same
// name - so the invariants that a human editor can break get asserted here.
func TestTemplateSizes(t *testing.T) {
	cases := []struct {
		category string
		want     int
	}{
		{string(CategoryUniversal), UniversalSize},
		{string(CategoryPlumbing), PlumbingSize},
		{string(CategoryWood), WoodSize},
		{string(CategoryWallpaper), WallpaperSize},
	}

	for _, tc := range cases {
		t.Run(tc.category, func(t *testing.T) {
			if got := Size(tc.category); got != tc.want {
				t.Errorf("Size(%q) = %d, want %d", tc.category, got, tc.want)
			}
		})
	}
}

// template_key is the shop-scoped unique index (db/migrations/000005), so a duplicated key inside
// one category makes seeding fail on the *second* insert - after the shop row is already written,
// rolling the whole creation back. a copy-pasted line is exactly how that happens.
func TestTemplateKeysAreUniqueAndFitTheColumn(t *testing.T) {
	const (
		maxKeyLen  = 60  // products.template_key VARCHAR(60)
		maxNameLen = 150 // products.name VARCHAR(150)
		maxUnitLen = 20  // products.unit VARCHAR(20)
	)

	for category := range templates {
		seenKeys := make(map[string]bool)
		for _, item := range Template(string(category)) {
			if seenKeys[item.Key] {
				t.Errorf("%s: duplicate template key %q", category, item.Key)
			}
			seenKeys[item.Key] = true

			if item.Key == "" || item.Name == "" || item.Unit == "" {
				t.Errorf("%s: item %q has an empty field: %+v", category, item.Key, item)
			}

			// products.category is no longer checked for width but for *membership*: it holds one of
			// the twelve shared codes now, and a code the app has no label for would render as a
			// blank group rather than as anything obviously wrong.
			if !IsValidProductCategory(string(item.Category)) {
				t.Errorf("%s: item %q has unknown product category %q", category, item.Key, item.Category)
			}

			// rune count, not len(): these are cyrillic names where one character is two bytes, and
			// postgres counts varchar limits in characters.
			if utf8.RuneCountInString(item.Key) > maxKeyLen ||
				utf8.RuneCountInString(item.Name) > maxNameLen ||
				utf8.RuneCountInString(item.Unit) > maxUnitLen {
				t.Errorf("%s: item %q has a value too wide for its column: %+v", category, item.Key, item)
			}
		}
	}
}

// the flutter app has an exhaustive switch over its own copy of this list, so a code added on one
// side and not the other is a missing label rather than a crash - which is exactly the kind of drift
// that goes unnoticed. this at least pins the go side: the codes are what the database stores and
// what the app switches on, so a rename here is a silent data migration.
func TestProductCategoryCodes(t *testing.T) {
	want := []string{
		"mixes", "blocks", "lumber", "metal", "fasteners", "roofing",
		"insulation", "electrical", "plumbing", "paints", "finishing", "tools",
	}

	if len(AllProductCategories) != len(want) {
		t.Fatalf("AllProductCategories has %d entries, want %d", len(AllProductCategories), len(want))
	}
	for i, code := range want {
		if string(AllProductCategories[i]) != code {
			t.Errorf("AllProductCategories[%d] = %q, want %q", i, AllProductCategories[i], code)
		}
		if !IsValidProductCategory(code) {
			t.Errorf("IsValidProductCategory(%q) = false, want true", code)
		}
	}

	// the old free-text values the column used to hold must not pass - migration 000006 remapped
	// them, and anything still shaped like display text is a caller that missed the change
	for _, invalid := range []string{"", "MIXES", "Крепёж", "Сантехника", "universal"} {
		if IsValidProductCategory(invalid) {
			t.Errorf("IsValidProductCategory(%q) = true, want false", invalid)
		}
	}
}

// Template hands back a copy precisely so a caller can't reach into the package's own memory. if
// that ever regresses, every shop created after the first mutation is seeded with corrupted data -
// silently, and only in production, since a fresh process starts clean again.
func TestTemplateReturnsACopy(t *testing.T) {
	first := Template(string(CategoryWood))
	first[0].Name = "mutated"

	if second := Template(string(CategoryWood)); second[0].Name == "mutated" {
		t.Fatal("Template() handed out the package's own slice - mutating it corrupted the template")
	}
}

func TestIsValidCategory(t *testing.T) {
	for _, valid := range []string{"universal", "plumbing", "wood", "wallpaper"} {
		if !IsValidCategory(valid) {
			t.Errorf("IsValidCategory(%q) = false, want true", valid)
		}
	}
	for _, invalid := range []string{"", "UNIVERSAL", "santehnika", "Универсальный"} {
		if IsValidCategory(invalid) {
			t.Errorf("IsValidCategory(%q) = true, want false", invalid)
		}
	}
}
