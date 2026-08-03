package catalog

// the vocabulary a single *product* is filed under, stored in products.category.
//
// this is one list for the whole app, not two: the same codes back the "Популярные категории" grid
// on the flutter home screen and the category dropdown on the product form. before this, the home
// grid had its own eight hardcoded labels while a product's category was free text typed by the
// owner, so nothing on the home screen could ever have been wired to a real product - "Крепёж" the
// tile and "крепеж" the typed string were unrelated values that only looked the same.
//
// like shops.category these are locale-neutral codes translated at the app boundary, which also
// fixes a second bug: the categories used to be stored as russian display text, so they stayed
// russian when the app was switched to uzbek.
type ProductCategory string

const (
	ProductMixes      ProductCategory = "mixes"      // Смеси - цемент, песок, штукатурка, клей, пена
	ProductBlocks     ProductCategory = "blocks"     // Кирпич и блоки
	ProductLumber     ProductCategory = "lumber"     // Пиломатериалы - доска, брус, фанера, ОСБ, ДСП
	ProductMetal      ProductCategory = "metal"      // Металлопрокат - арматура, уголок, профиль
	ProductFasteners  ProductCategory = "fasteners"  // Крепёж - гвозди, саморезы, дюбели, анкеры
	ProductRoofing    ProductCategory = "roofing"    // Кровля
	ProductInsulation ProductCategory = "insulation" // Изоляция
	ProductElectrical ProductCategory = "electrical" // Электрика
	ProductPlumbing   ProductCategory = "plumbing"   // Сантехника
	ProductPaints     ProductCategory = "paints"     // Краски
	ProductFinishing  ProductCategory = "finishing"  // Отделка - плитка, ламинат, обои, двери, окна
	ProductTools      ProductCategory = "tools"      // Инструменты
)

// AllProductCategories is the canonical order - the order the flutter dropdown and the home grid
// both render in, roughly following the order of a build: structure first, finishes last.
//
// a slice rather than only a map because order is part of the contract here; the map below exists
// purely so validation is a lookup instead of a linear scan.
var AllProductCategories = []ProductCategory{
	ProductMixes,
	ProductBlocks,
	ProductLumber,
	ProductMetal,
	ProductFasteners,
	ProductRoofing,
	ProductInsulation,
	ProductElectrical,
	ProductPlumbing,
	ProductPaints,
	ProductFinishing,
	ProductTools,
}

var productCategorySet = func() map[ProductCategory]bool {
	set := make(map[ProductCategory]bool, len(AllProductCategories))
	for _, c := range AllProductCategories {
		set[c] = true
	}
	return set
}()

// IsValidProductCategory reports whether a category code sent by the app is one of ours.
//
// there is deliberately no CHECK constraint on products.category to match this (unlike
// shops.category and products.availability, which both have one). those two are structural - three
// stock states, four shop kinds - whereas this list is *content*: it will grow as the home grid
// grows, and every growth would otherwise cost a migration. the write path is narrow enough that
// validating here is sufficient, since the only two statements that set the column are
// CreateCustomProduct and UpdateProduct, both of which come through this function.
func IsValidProductCategory(code string) bool {
	return productCategorySet[ProductCategory(code)]
}
