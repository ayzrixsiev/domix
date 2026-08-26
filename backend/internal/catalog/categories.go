package catalog

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

func IsValidProductCategory(code string) bool {
	return productCategorySet[ProductCategory(code)]
}
