package catalog

// the templates are ~170 lines of hand-typed data transcribed from /products.md. they fail by
// producing 98 tiles or a duplicate key, not by failing to compile, so the invariants a human
// editor can break are asserted here.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

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
		if got := Size(tc.category); got != tc.want {
			t.Errorf("Size(%q) = %d, want %d", tc.category, got, tc.want)
		}
	}
}

// template_key is a shop-scoped unique index, so a duplicated key makes seeding fail on the *second*
// insert - after the shop row is written, rolling the whole creation back. a copy-pasted line is
// exactly how that happens.
func TestTemplateKeysAreUniqueAndFitTheColumn(t *testing.T) {
	const (
		maxKeyLen  = 60  // products.template_key VARCHAR(60)
		maxNameLen = 150 // products.name VARCHAR(150)
		maxUnitLen = 20  // products.unit VARCHAR(20)
	)

	for category := range templates {
		seen := make(map[string]bool)
		for _, item := range Template(string(category)) {
			if seen[item.Key] {
				t.Errorf("%s: duplicate template key %q", category, item.Key)
			}
			seen[item.Key] = true

			if item.Key == "" || item.Name == "" || item.Unit == "" {
				t.Errorf("%s: item %q has an empty field: %+v", category, item.Key, item)
			}
			if !IsValidProductCategory(string(item.Category)) {
				t.Errorf("%s: item %q has unknown product category %q", category, item.Key, item.Category)
			}
			// rune count, not len(): cyrillic characters are two bytes and postgres counts varchar
			// limits in characters
			if utf8.RuneCountInString(item.Key) > maxKeyLen ||
				utf8.RuneCountInString(item.Name) > maxNameLen ||
				utf8.RuneCountInString(item.Unit) > maxUnitLen {
				t.Errorf("%s: item %q has a value too wide for its column: %+v", category, item.Key, item)
			}
		}
	}
}

// the workflow this guards: the founder drops a photo into /photos/<category>/ and adds a row to
// /products.md, and the two have to end up pointing at each other. a row whose file is missing is
// a tile with a broken image in every shop of the category, and nothing in the app says why - the
// request just 404s and the placeholder banner shows instead.
//
// listed per category rather than run over every template, because wood and обои legitimately have
// no photos yet: wood has none taken, and an обои slot names no product to photograph. adding a
// category here is the last step of shooting its catalogue.
func TestTemplatesHaveAPhotoForEveryProduct(t *testing.T) {
	photographed := []Category{CategoryUniversal, CategoryPlumbing}

	// backend/internal/catalog -> repo root
	dir := filepath.Join("..", "..", "..", "photos")
	if _, err := os.Stat(dir); err != nil {
		t.Skipf("no %s directory here (%v) - skipping", dir, err)
	}

	for _, category := range photographed {
		t.Run(string(category), func(t *testing.T) {
			seen := make(map[string]string)
			for _, item := range Template(string(category)) {
				if item.Image == "" {
					t.Errorf("%s has no photo - add one to /photos/%s/ and to /products.md", item.Key, category)
					continue
				}
				if other, taken := seen[item.Image]; taken {
					t.Errorf("%s and %s both use photo %s", other, item.Key, item.Image)
				}
				seen[item.Image] = item.Key

				path := filepath.Join(dir, item.ImagePath(category))
				if _, err := os.Stat(path); err != nil {
					t.Errorf("%s points at %s, which does not exist", item.Key, path)
				}
			}
		})
	}
}

// the app's exhaustive switch over its own copy of this list means a code added on one side and not
// the other is a missing label rather than a crash - the kind of drift that goes unnoticed. this
// pins the go side.
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

	// the old free-text values must not pass - migration 000006 remapped them, and anything still
	// shaped like display text is a caller that missed the change
	for _, invalid := range []string{"", "MIXES", "Крепёж", "Сантехника", "universal"} {
		if IsValidProductCategory(invalid) {
			t.Errorf("IsValidProductCategory(%q) = true, want false", invalid)
		}
	}
}

// if this regresses, every shop created after the first accidental mutation is seeded with corrupted
// data - silently, and only in production, since a fresh process starts clean again.
func TestTemplateReturnsACopy(t *testing.T) {
	first := Template(string(CategoryWood))
	first[0].Name = "mutated"

	if second := Template(string(CategoryWood)); second[0].Name == "mutated" {
		t.Fatal("Template() handed out the package's own slice - mutating it corrupted the template")
	}
}

// a slot that stopped being recognised would silently become an ordinary template row: the обои
// owner would find the name locked to "Обои премиум (Россия)" with no error explaining it.
func TestWallpaperSlotsAreOwnerNamed(t *testing.T) {
	slots := Template(string(CategoryWallpaper))

	for _, item := range slots {
		if !IsOwnerNamedSlot(item.Key) {
			t.Errorf("IsOwnerNamedSlot(%q) = false - every обои row is a slot", item.Key)
		}
		// the unit is what keeps ten different rolls a comparable basket
		if item.Unit != "рулон" {
			t.Errorf("slot %q has unit %q, want \"рулон\"", item.Key, item.Unit)
		}
	}

	// the founder's split, counted off the key prefixes rather than the names: the key is the part
	// that can never be edited, and it is what the index groups by
	tiers := map[string]int{}
	for _, item := range slots {
		switch {
		case strings.HasPrefix(item.Key, "wallpaper.premium_"):
			tiers["premium"]++
		case strings.HasPrefix(item.Key, "wallpaper.standard_"):
			tiers["standard"]++
		case strings.HasPrefix(item.Key, "wallpaper.econom_"):
			tiers["econom"]++
		default:
			t.Errorf("slot %q belongs to no tier", item.Key)
		}
	}
	for tier, want := range map[string]int{"premium": 3, "standard": 4, "econom": 3} {
		if tiers[tier] != want {
			t.Errorf("%s slots = %d, want %d", tier, tiers[tier], want)
		}
	}
}

// the other three templates name real products, and renaming one would break exactly what the
// template exists to guarantee - that "Кнауф Ротбанд, 25 кг" means the same thing everywhere.
func TestNonWallpaperTemplatesAreNotOwnerNamed(t *testing.T) {
	for _, category := range []Category{CategoryUniversal, CategoryPlumbing, CategoryWood} {
		for _, item := range Template(string(category)) {
			if IsOwnerNamedSlot(item.Key) {
				t.Errorf("IsOwnerNamedSlot(%q) = true - %s names its own products", item.Key, category)
			}
		}
	}

	// the empty string is what a caller reads off an invalid pgtype.Text, i.e. a product the owner
	// added themselves
	if IsOwnerNamedSlot("") {
		t.Error(`IsOwnerNamedSlot("") = true, want false`)
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
