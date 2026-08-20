package catalog

// the templates moved out of this package's source and into `product_templates` (migration 000014),
// so these tests split in two.
//
// The first half is about the in-memory store: Load replacing the world atomically, Template handing
// out copies, and the slot key set being derived from the declared owner-named *categories* rather
// than written down separately. Those run on synthetic rows and need no database.
//
// The second half is about the real table, and it is what used to be asserted against the Go
// literal: unique keys, values that fit the columns they get copied into, product categories the app
// has a label for, and photos that exist on disk. Those need the database, and skip cleanly without
// one.

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"
)

func rows(shopCategory string, keys ...string) []Row {
	out := make([]Row, 0, len(keys))
	for _, key := range keys {
		out = append(out, Row{
			ShopCategory: shopCategory, Key: key, Name: "Товар " + key,
			Category: "tools", Unit: "шт",
		})
	}
	return out
}

// ─────────────────────────── the in-memory store ───────────────────────────

// if this regresses, every shop created after the first accidental mutation is seeded with corrupted
// data - silently, and only in production, since a fresh process starts clean again.
func TestTemplateReturnsACopy(t *testing.T) {
	Load(rows("wood", "wood.a", "wood.b"))

	first := Template("wood")
	first[0].Name = "mutated"

	if second := Template("wood"); second[0].Name == "mutated" {
		t.Fatal("Template() handed out the package's own slice - mutating it corrupted the template")
	}
}

// Load replaces the whole map rather than merging into it, so a product removed from a template
// through the panel is actually gone from the next shop created - not still there because nothing
// deleted it from memory.
func TestLoadReplacesRatherThanMerges(t *testing.T) {
	Load(rows("wood", "wood.a", "wood.b", "wood.c"))
	if got := Size("wood"); got != 3 {
		t.Fatalf("Size after first load = %d, want 3", got)
	}

	Load(rows("wood", "wood.a"))
	if got := Size("wood"); got != 1 {
		t.Errorf("Size after reload = %d, want 1 - Load merged instead of replacing", got)
	}
	if Template("wood")[0].Key != "wood.a" {
		t.Error("the surviving row is not the one that was loaded")
	}
}

// a slot that stopped being recognised would silently become an ordinary template row: the обои
// owner would find the name locked to the placeholder with no error explaining it. the key set is
// rebuilt by Load off ownerNamedCategories, so this also pins that the derivation survives a reload.
func TestOwnerNamedSlotsAreDerivedFromTheCategory(t *testing.T) {
	Load(append(rows("wallpaper", "wallpaper.premium_ru", "wallpaper.econom_cn_1"),
		rows("wood", "wood.board")...))

	for _, key := range []string{"wallpaper.premium_ru", "wallpaper.econom_cn_1"} {
		if !IsOwnerNamedSlot(key) {
			t.Errorf("IsOwnerNamedSlot(%q) = false - every обои row is a slot", key)
		}
	}
	if IsOwnerNamedSlot("wood.board") {
		t.Error("IsOwnerNamedSlot(\"wood.board\") = true - wood names its own products")
	}
	// the empty string is what a caller reads off an invalid pgtype.Text, i.e. a product the owner
	// added themselves
	if IsOwnerNamedSlot("") {
		t.Error(`IsOwnerNamedSlot("") = true, want false`)
	}

	if !IsOwnerNamedCategory("wallpaper") || IsOwnerNamedCategory("wood") {
		t.Error("IsOwnerNamedCategory disagrees with IsOwnerNamedSlot about which categories are slot-based")
	}
}

// emptying a template from the panel must not make its code stop being a category - the add-store
// form would start rejecting it, which is a much stranger failure than an empty catalogue.
func TestCategoryValidityDoesNotDependOnWhatIsLoaded(t *testing.T) {
	Load(rows("wood", "wood.a"))

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

// the app's exhaustive switch over its own copy of this list means a code added on one side and not
// the other is a missing label rather than a crash - the kind of drift that goes unnoticed.
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

	// the old free-text values must not pass - migration 000006 remapped them
	for _, invalid := range []string{"", "MIXES", "Крепёж", "Сантехника", "universal"} {
		if IsValidProductCategory(invalid) {
			t.Errorf("IsValidProductCategory(%q) = true, want false", invalid)
		}
	}
}

// ─────────────────────────── the real table ───────────────────────────

type storedRow struct {
	shopCategory, key, name, category, unit, imagePath string
}

func storedTemplates(t *testing.T) []storedRow {
	t.Helper()

	if os.Getenv("DB_URL") == "" {
		_ = godotenv.Load(filepath.Join("..", "..", "..", ".env"))
	}
	dbURL := os.Getenv("DB_URL")
	if dbURL == "" {
		t.Skip("DB_URL is not set - skipping the tests that read product_templates")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	t.Cleanup(cancel)

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		t.Skipf("cannot reach the database (%v) - skipping", err)
	}
	t.Cleanup(func() { _ = conn.Close(context.Background()) })

	found, err := conn.Query(ctx,
		`SELECT shop_category, template_key, name, category, unit, COALESCE(image_path, '')
		   FROM product_templates ORDER BY shop_category, id`)
	if err != nil {
		t.Fatalf("read product_templates: %v", err)
	}
	defer found.Close()

	var out []storedRow
	for found.Next() {
		var r storedRow
		if err := found.Scan(&r.shopCategory, &r.key, &r.name, &r.category, &r.unit, &r.imagePath); err != nil {
			t.Fatalf("scan: %v", err)
		}
		out = append(out, r)
	}
	if len(out) == 0 {
		t.Fatal("product_templates is empty - run the migrations")
	}
	return out
}

// every value here is copied verbatim into `products` at seeding, so a row that fits this table and
// not that one fails at shop creation - the worst possible moment to find out. the UNIQUE constraint
// covers the key; these are the checks the schema cannot make.
func TestStoredTemplatesFitTheProductsTable(t *testing.T) {
	const (
		maxKeyLen  = 60  // products.template_key VARCHAR(60)
		maxNameLen = 150 // products.name VARCHAR(150)
		maxUnitLen = 20  // products.unit VARCHAR(20)
	)

	seen := map[string]bool{}
	for _, row := range storedTemplates(t) {
		if seen[row.key] {
			t.Errorf("duplicate template key %q", row.key)
		}
		seen[row.key] = true

		if strings.TrimSpace(row.name) == "" || strings.TrimSpace(row.unit) == "" {
			t.Errorf("%s: empty name or unit", row.key)
		}
		if !IsValidCategory(row.shopCategory) {
			t.Errorf("%s: unknown shop category %q", row.key, row.shopCategory)
		}
		if !IsValidProductCategory(row.category) {
			t.Errorf("%s: unknown product category %q - the app has no label for it", row.key, row.category)
		}
		// rune counts, not len(): cyrillic characters are two bytes and postgres counts varchar
		// limits in characters
		if utf8.RuneCountInString(row.key) > maxKeyLen ||
			utf8.RuneCountInString(row.name) > maxNameLen ||
			utf8.RuneCountInString(row.unit) > maxUnitLen {
			t.Errorf("%s: a value is too wide for the products column it is copied into", row.key)
		}
	}
}

// the workflow this guards: a photo is dropped into /photos/<category>/ and a row points at it. a
// row whose file is missing is a broken image on a tile in every shop of the category, and nothing
// in the app says why - the request just 404s and the placeholder shows instead.
//
// only rows that *claim* a photo are checked. wood has none taken and an обои slot names no product
// to photograph, so an empty image_path is a legitimate state rather than a missing file.
func TestStoredTemplatePhotosExist(t *testing.T) {
	// backend/internal/catalog -> repo root
	dir := filepath.Join("..", "..", "..", "photos")
	if _, err := os.Stat(dir); err != nil {
		t.Skipf("no %s directory here (%v) - skipping", dir, err)
	}

	seen := map[string]string{}
	for _, row := range storedTemplates(t) {
		if row.imagePath == "" {
			continue
		}
		if other, taken := seen[row.imagePath]; taken && other != row.key {
			// two rows sharing a photo is legal for the same product in two sizes, but not within
			// one category's list, where it means a number was pasted twice
			t.Logf("note: %s and %s share photo %s", other, row.key, row.imagePath)
		}
		seen[row.imagePath] = row.key

		if _, err := os.Stat(filepath.Join(dir, row.imagePath)); err != nil {
			t.Errorf("%s points at %s, which does not exist", row.key, row.imagePath)
		}
	}
}
