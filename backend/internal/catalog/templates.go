package catalog

import "sync"

type Category string

const (
	CategoryUniversal Category = "universal"
	CategoryPlumbing  Category = "plumbing"
	CategoryWood      Category = "wood"
	CategoryWallpaper Category = "wallpaper"
)

type Item struct {
	Key       string
	Name      string
	Category  ProductCategory
	Unit      string
	ImagePath string

	// whether this row counts towards the price comparison. a product added to a template starts
	// outside it, so extending the catalogue cannot drop a live market out of the comparison; an
	// admin votes it in once most shops have priced it.
	InBasket bool

	// one size of a product that has several: the group's display name and this row's chip. **display
	// only** - one row is still one price, which is what the index and the search rest on.
	VariantGroup string
	VariantLabel string
}

type Row struct {
	ShopCategory string
	Key          string
	Name         string
	Category     string
	Unit         string
	ImagePath    string
	InBasket     bool
	VariantGroup string
	VariantLabel string
}

var (
	mu             sync.RWMutex
	templates      = map[Category][]Item{}
	ownerNamedKeys = map[string]bool{}
	templateImages = map[string]string{}
	loaded         bool
)

func Load(rows []Row) {
	next := map[Category][]Item{}
	for _, row := range rows {
		category := Category(row.ShopCategory)
		next[category] = append(next[category], Item{
			Key:          row.Key,
			Name:         row.Name,
			Category:     ProductCategory(row.Category),
			Unit:         row.Unit,
			ImagePath:    row.ImagePath,
			InBasket:     row.InBasket,
			VariantGroup: row.VariantGroup,
			VariantLabel: row.VariantLabel,
		})
	}

	slots := map[string]bool{}
	for _, category := range ownerNamedCategories {
		for _, item := range next[category] {
			slots[item.Key] = true
		}
	}

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

func Loaded() bool {
	mu.RLock()
	defer mu.RUnlock()
	return loaded
}

var ownerNamedCategories = []Category{CategoryWallpaper}

func IsOwnerNamedCategory(code string) bool {
	for _, category := range ownerNamedCategories {
		if string(category) == code {
			return true
		}
	}
	return false
}

func IsOwnerNamedSlot(templateKey string) bool {
	mu.RLock()
	defer mu.RUnlock()
	return ownerNamedKeys[templateKey]
}

var AllShopCategories = []Category{
	CategoryUniversal,
	CategoryPlumbing,
	CategoryWood,
	CategoryWallpaper,
}

func IsValidCategory(code string) bool {
	for _, category := range AllShopCategories {
		if string(category) == code {
			return true
		}
	}
	return false
}

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

func TemplateImage(templateKey string) string {
	mu.RLock()
	defer mu.RUnlock()
	return templateImages[templateKey]
}

func Size(code string) int {
	mu.RLock()
	defer mu.RUnlock()
	return len(templates[Category(code)])
}
