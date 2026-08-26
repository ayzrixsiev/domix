package catalog

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

	// test-only, for the one declaration of the "_thumb beside the master" rule. no cycle: nothing
	// in imagestore knows the catalogue exists.
	"domix/backend/internal/imagestore"
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

func TestTemplateReturnsACopy(t *testing.T) {
	Load(rows("wood", "wood.a", "wood.b"))

	first := Template("wood")
	first[0].Name = "mutated"

	if second := Template("wood"); second[0].Name == "mutated" {
		t.Fatal("Template() handed out the package's own slice - mutating it corrupted the template")
	}
}

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

	if IsOwnerNamedSlot("") {
		t.Error(`IsOwnerNamedSlot("") = true, want false`)
	}

	if !IsOwnerNamedCategory("wallpaper") || IsOwnerNamedCategory("wood") {
		t.Error("IsOwnerNamedCategory disagrees with IsOwnerNamedSlot about which categories are slot-based")
	}
}

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

	for _, invalid := range []string{"", "MIXES", "Крепёж", "Сантехника", "universal"} {
		if IsValidProductCategory(invalid) {
			t.Errorf("IsValidProductCategory(%q) = true, want false", invalid)
		}
	}
}

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

func TestStoredTemplatesFitTheProductsTable(t *testing.T) {
	const (
		maxKeyLen  = 60
		maxNameLen = 150
		maxUnitLen = 20
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

		if utf8.RuneCountInString(row.key) > maxKeyLen ||
			utf8.RuneCountInString(row.name) > maxNameLen ||
			utf8.RuneCountInString(row.unit) > maxUnitLen {
			t.Errorf("%s: a value is too wide for the products column it is copied into", row.key)
		}
	}
}

func TestStoredTemplatePhotosExist(t *testing.T) {

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
			t.Logf("note: %s and %s share photo %s", other, row.key, row.imagePath)
		}
		seen[row.imagePath] = row.key

		if _, err := os.Stat(filepath.Join(dir, row.imagePath)); err != nil {
			t.Errorf("%s points at %s, which does not exist", row.key, row.imagePath)
		}

		// **the thumbnail is not optional and nothing else would catch it missing.** Only the
		// master's path is stored; the api derives the thumbnail's by appending `_thumb`, sends both
		// urls, and the app loads the small one in every grid. So a catalogue shot without its
		// thumbnail is a tile that is blank in every shop of that category - and generating them is a
		// `magick` line somebody runs by hand when a category is photographed (CLAUDE.md §7), which
		// is exactly the kind of step that gets skipped.
		thumb := imagestore.ThumbPath(row.imagePath)
		if _, err := os.Stat(filepath.Join(dir, thumb)); err != nil {
			t.Errorf("%s points at %s, whose thumbnail %s does not exist - run the resize command in "+
				"CLAUDE.md §7 over that directory", row.key, row.imagePath, thumb)
		}
	}
}
