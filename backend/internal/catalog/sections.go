package catalog

// the groups a shop's «Категории» sheet splits its grid by. **separate from ProductCategory**: a category is
// what the home screen browses across every shop, a section only orders one shop's own catalogue. the app
// holds the ru/uz names and the order.
var sections = map[string]bool{
	// universal
	"tapes_abrasives":     true, // Ленты, расходники, абразивы и диски
	"drills_hand_tools":   true, // Свёрла и ручной инструмент
	"electrical_lighting": true, // Электрика и освещение
	"fasteners_mounting":  true, // Крепёж и монтаж
	"mixes_paints":        true, // Смеси, клеи, краски и химия
	"films_sheets":        true, // Плёнки, изоляция и листовые материалы

	// plumbing
	"pipes_insulation":   true, // Трубы и теплоизоляция
	"ppr_fittings":       true, // PPR-фитинги VERO
	"valves_vero":        true, // Краны и вентили VERO
	"sewer":              true, // Канализация VERO
	"threaded_fittings":  true, // Металлические резьбовые фитинги
	"ktm_fittings":       true, // Фитинги KTM
	"valves_kas":         true, // Краны KAS
	"cistern_toilet":     true, // Бачок и унитаз
	"siphons":            true, // Сифоны
	"drains":             true, // Трапы
	"washing_machine":    true, // Для стиральной машины
	"filters_cartridges": true, // Фильтры и картриджи
	"mixer_parts":        true, // Комплектующие для смесителей
	"hoses":              true, // Гибкие подводки и шланги
	"mixers":             true, // Смесители
}

func IsValidSection(code string) bool {
	return sections[code]
}
