package catalog

// the chips a shop's grid is split by. **separate from ProductCategory**: a category is what the home
// screen browses across every shop, a section only orders one shop's own catalogue. the app holds the
// ru/uz names and the order.
var sections = map[string]bool{
	"tapes_abrasives":     true, // Ленты, расходники, абразивы и диски
	"drills_hand_tools":   true, // Свёрла и ручной инструмент
	"electrical_lighting": true, // Электрика и освещение
	"fasteners_mounting":  true, // Крепёж и монтаж
	"mixes_paints":        true, // Смеси, клеи, краски и химия
	"films_sheets":        true, // Плёнки, изоляция и листовые материалы
}

func IsValidSection(code string) bool {
	return sections[code]
}
