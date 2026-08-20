// package catalog holds the ready-made product list a new shop's catalogue is seeded from. every
// shop of a category starts with the same rows differing only in price, which is the only reason
// two shops' baskets can be compared at all.
//
// **the lists live in the database now (migration 000014), not in this file.** they used to be a Go
// literal here, on the reasoning that nothing joins against them at runtime so a table would cost a
// migration per edit and buy an admin UI that did not exist. both halves of that flipped: the
// founder edits catalogues often enough that a rebuild per edit is the cost, and the admin UI
// exists. What did *not* flip is the performance argument - nothing joins against the table either.
// It is read once at startup into the memory this package holds, and re-read when an admin edits
// it, so every call below is still a map lookup.
//
// That in-memory copy is load-bearing rather than an optimisation. IsOwnerNamedSlot is asked once
// per product in every product response - a hundred times for one Универсальный catalogue - and
// Template() is read inside the transaction that creates a shop. Either of those going to the
// database per call would be a different kind of program.
package catalog

import "sync"

// Category is a shop's kind, stored in shops.category. locale-neutral codes - the russian and uzbek
// names live in the flutter app's AppLocalizations, so adding a language never touches the backend.
type Category string

const (
	CategoryUniversal Category = "universal" // Универсальный
	CategoryPlumbing  Category = "plumbing"  // Сантехника
	CategoryWood      Category = "wood"      // Древесные материалы
	CategoryWallpaper Category = "wallpaper" // Обои
)

// one row of a template, and one row of `products` once seeded into a shop.
type Item struct {
	// becomes products.template_key and must stay stable forever: it is what identifies "the same
	// product across every shop", which is what the basket index is built on. renaming an item is
	// fine, changing its key orphans every shop already seeded with the old one - which is why the
	// admin api refuses to edit this column.
	Key  string
	Name string

	// one of the twelve shared codes in categories.go, typed so a typo fails to compile
	Category ProductCategory

	Unit string // шт, кг, мешок ...

	// where the photo lives inside the served images folder, e.g. "universal/001.jpg". empty for a
	// row with no photo. the full relative path rather than a bare filename, because that is what
	// product_templates.image_path and products.image_path both store - a bare name would need the
	// category threaded through every call site to be usable.
	ImagePath string
}

// Row is one record as it comes out of product_templates. a separate type from Item so this package
// does not import db (which would make the dependency point the wrong way) and so the loader can be
// handed rows from anywhere - a query, a test, a fixture.
type Row struct {
	ShopCategory string
	Key          string
	Name         string
	Category     string
	Unit         string
	ImagePath    string
}

// the process-wide copy of product_templates, and everything that reads it.
//
// a RWMutex rather than a sync.Map or an atomic pointer: reads dominate overwhelmingly (every
// product response asks IsOwnerNamedSlot) and writes happen when an administrator presses save, so
// the cheap-read lock is the right one. the whole map is replaced on each Load rather than mutated
// in place, so a reader either sees the old templates or the new ones, never a half-applied edit.
var (
	mu             sync.RWMutex
	templates      = map[Category][]Item{}
	ownerNamedKeys = map[string]bool{}
	templateImages = map[string]string{}
	loaded         bool
)

// Load replaces the in-memory templates with `rows`. Called once at startup and again after every
// admin edit; nothing else may write to this package's state.
//
// rows arrive already ordered by (shop_category, id) - the order they are seeded in, and
// therefore the order an owner prices them in.
func Load(rows []Row) {
	next := map[Category][]Item{}
	for _, row := range rows {
		category := Category(row.ShopCategory)
		next[category] = append(next[category], Item{
			Key:       row.Key,
			Name:      row.Name,
			Category:  ProductCategory(row.Category),
			Unit:      row.Unit,
			ImagePath: row.ImagePath,
		})
	}

	// the slot key set is derived here rather than looked up per call, and it is derived from the
	// *categories* declared owner-named rather than from a hand-written list of keys - a key list
	// would be a second copy of "which rows are slots" that can drift from the template describing
	// them, which is the same reason products.is_template was rejected.
	slots := map[string]bool{}
	for _, category := range ownerNamedCategories {
		for _, item := range next[category] {
			slots[item.Key] = true
		}
	}

	// key -> the catalogue photo that key was seeded with, so removing an owner's own photo from a
	// template row can put back the shot the row arrived with rather than leaving it blank. derived
	// here for the same reason the slot keys are: it is the template's own data, and a second copy
	// maintained anywhere else could disagree with it after an admin edit.
	images := map[string]string{}
	for _, items := range next {
		for _, item := range items {
			if item.ImagePath != "" {
				images[item.Key] = item.ImagePath
			}
		}
	}

	mu.Lock()
	defer mu.Unlock()
	templates = next
	ownerNamedKeys = slots
	templateImages = images
	loaded = true
}

// Loaded reports whether Load has ever run. main.go treats false as fatal: an api that answers
// requests with no templates creates shops with empty catalogues, and an empty catalogue is
// indistinguishable from a shop whose owner has not started - it would corrupt data quietly rather
// than fail loudly.
func Loaded() bool {
	mu.RLock()
	defer mu.RUnlock()
	return loaded
}

// the categories whose template is a set of slots rather than a set of products. declared as
// categories, not as a hand-written list of keys: a key list would be a second copy of "which rows
// are slots" that can drift from the template describing them.
var ownerNamedCategories = []Category{CategoryWallpaper}

// IsOwnerNamedCategory reports whether a whole category's template is slots rather than products.
//
// asked by the template sync (internal/endpoints/admin.go), which has to decide whether rewriting
// product names across every existing shop is a correction or a destruction. for обои it is a
// destruction: the name on a slot is the owner's own wallpaper, and the template's is a placeholder
// describing what belongs there. derived from the same ownerNamedCategories declaration
// IsOwnerNamedSlot uses, so the two can never disagree about which categories are slot-based.
func IsOwnerNamedCategory(code string) bool {
	for _, category := range ownerNamedCategories {
		if string(category) == code {
			return true
		}
	}
	return false
}

// IsOwnerNamedSlot reports whether this template key names a slot the owner fills in rather than a
// product the template names for them. asked of the key rather than of the shop's category, because
// the handler already holds the product row and would otherwise need a second query.
func IsOwnerNamedSlot(templateKey string) bool {
	mu.RLock()
	defer mu.RUnlock()
	return ownerNamedKeys[templateKey]
}

// AllShopCategories is the canonical order: the "Лучшие предложения" tab strip and the add-store
// picker. a slice rather than ranging the map, because go randomises map iteration order and the
// tabs would reshuffle on every request.
var AllShopCategories = []Category{
	CategoryUniversal,
	CategoryPlumbing,
	CategoryWood,
	CategoryWallpaper,
}

// IsValidCategory reports whether a category code sent by the app is one we hold a template for.
// the database CHECK would reject an unknown value too, but as a 500 with a postgres error in the
// log instead of a 400 naming the field.
func IsValidCategory(code string) bool {
	// checked against the declared list rather than against what happens to be loaded, so a
	// category whose template is momentarily empty (every row deleted from the panel) is still a
	// category - the alternative is that emptying a template silently makes its code invalid and
	// the add-store form starts rejecting it.
	for _, category := range AllShopCategories {
		if string(category) == code {
			return true
		}
	}
	return false
}

// Template returns the rows a new shop of this category is seeded with, or nil for an unknown one.
//
// the copy is deliberate: a map lookup hands back the slice header, so a caller assigning to an
// element would rewrite the template for every shop created afterwards in this process.
func Template(code string) []Item {
	mu.RLock()
	defer mu.RUnlock()

	items, ok := templates[Category(code)]
	if !ok {
		return nil
	}
	out := make([]Item, len(items))
	copy(out, items)
	return out
}

// TemplateImage is the catalogue photo a template row was seeded with, or "" for a key the
// templates name no photo for - which is every обои slot, and every row in a category whose
// catalogue has not been photographed yet.
//
// Asked by DELETE /api/products/{id}/image: an owner removing the photo they uploaded onto a seeded
// row should get the shared catalogue shot back, not an empty tile. Their own products have no
// template key and so no default, which is the "" case.
func TemplateImage(templateKey string) string {
	mu.RLock()
	defer mu.RUnlock()
	return templateImages[templateKey]
}

// Size is how many products a shop of this category starts with - the "Готовый каталог: 100 товаров"
// hint in the create-shop picker.
func Size(code string) int {
	mu.RLock()
	defer mu.RUnlock()
	return len(templates[Category(code)])
}
