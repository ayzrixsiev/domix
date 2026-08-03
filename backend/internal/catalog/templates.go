// package catalog holds the ready-made product list a shop's catalogue is seeded from when the shop
// is created. every shop of the same category starts with exactly the same rows, differing only in
// the price each owner sets - which is the whole point: a customer comparing two сантехника shops is
// comparing the same products, and the "average check" the map advertises only means something if
// every shop is averaging the same basket.
//
// these live in go rather than in a database table on purpose. a template is a *product* decision
// (which items are popular enough to be in it) that changes by editing this file and redeploying,
// and nothing joins against it at runtime - CreateShop copies the rows into `products` once and the
// copies are what the app reads forever after. a table would buy an admin ui we don't have yet and
// cost a migration every time the list changes.
package catalog

// Category is a shop's kind, stored in shops.category. the string values are the locale-neutral
// codes the database CHECK constraint accepts (see db/migrations/000005) - the russian/uzbek names
// the owner actually picks from live in the flutter app's AppLocalizations, so adding a language
// never touches the backend.
type Category string

const (
	CategoryUniversal Category = "universal" // Универсальный - a general construction shop
	CategoryPlumbing  Category = "plumbing"  // Сантехника
	CategoryWood      Category = "wood"      // Дерево
	CategoryWallpaper Category = "wallpaper" // Обои
)

// one row of a template, and one row of `products` once it has been seeded into a shop.
//
// Key becomes products.template_key and must stay stable forever: it is what identifies "the same
// product across every shop" once cross-shop price comparison gets built. renaming an item is fine,
// changing its key is not - that would orphan every shop already seeded with the old one.
type Item struct {
	Key  string
	Name string

	// which of the twelve shared product categories this item is filed under - the same list the
	// app's "Популярные категории" grid is built from (see categories.go). a typed constant rather
	// than a free string, because a typo in 120 hand-written lines is otherwise only discovered
	// when an owner sees a tile in the wrong group; templates_test.go asserts every one is valid.
	Category ProductCategory

	Unit string // unit of measurement: шт, м², мешок ...
}

// the sizes the founder specified: 50 popular products for the two broad categories, 10 for the two
// narrow ones. asserted in templates_test.go so a hand-edit that drops or duplicates a row is caught
// by `go test` rather than by a shop owner finding 49 tiles.
const (
	UniversalSize = 50
	PlumbingSize  = 50
	WoodSize      = 10
	WallpaperSize = 10
)

// map access is by value, and returning the slice directly would hand the caller a window into this
// package's own memory - one accidental write and every shop created afterwards is seeded wrong.
// Template copies before returning; see the comment there.
var templates = map[Category][]Item{
	CategoryUniversal: {
		{"universal.cement_m400", "Цемент М400, 50 кг", ProductMixes, "мешок"},
		{"universal.cement_m500", "Цемент М500, 50 кг", ProductMixes, "мешок"},
		{"universal.sand", "Песок строительный", ProductMixes, "м³"},
		{"universal.gravel_5_20", "Щебень фракция 5-20", ProductMixes, "м³"},
		{"universal.brick_common", "Кирпич керамический рядовой", ProductBlocks, "шт"},
		{"universal.brick_facing", "Кирпич облицовочный", ProductBlocks, "шт"},
		{"universal.gasblock", "Газоблок 600х300х200", ProductBlocks, "шт"},
		{"universal.foamblock", "Пеноблок 600х300х200", ProductBlocks, "шт"},
		{"universal.cinderblock", "Шлакоблок 390х190х190", ProductBlocks, "шт"},
		{"universal.osb_9", "Плита ОСБ-3, 9 мм", ProductLumber, "лист"},
		{"universal.plywood_10", "Фанера ФК, 10 мм", ProductLumber, "лист"},
		{"universal.drywall_12", "Гипсокартон стеновой, 12.5 мм", ProductFinishing, "лист"},
		{"universal.profile_cd", "Профиль CD 60х27", ProductMetal, "шт"},
		{"universal.profile_ud", "Профиль UD 28х27", ProductMetal, "шт"},
		{"universal.plaster_gypsum", "Штукатурка гипсовая, 30 кг", ProductMixes, "мешок"},
		{"universal.putty_finish", "Шпаклёвка финишная, 20 кг", ProductMixes, "мешок"},
		{"universal.tile_glue", "Клей плиточный, 25 кг", ProductMixes, "мешок"},
		{"universal.primer_deep", "Грунтовка глубокого проникновения, 10 л", ProductMixes, "канистра"},
		{"universal.paint_water", "Краска водоэмульсионная, 15 кг", ProductPaints, "ведро"},
		{"universal.enamel_pf115", "Эмаль ПФ-115, 2.7 кг", ProductPaints, "банка"},
		{"universal.foam_750", "Пена монтажная, 750 мл", ProductMixes, "баллон"},
		{"universal.sealant_silicone", "Герметик силиконовый, 280 мл", ProductMixes, "туба"},
		{"universal.rebar_12", "Арматура А500С, 12 мм", ProductMetal, "м"},
		{"universal.masonry_mesh", "Сетка кладочная 50х50", ProductMetal, "м²"},
		{"universal.angle_50", "Уголок стальной 50х50", ProductMetal, "м"},
		{"universal.pipe_40x20", "Труба профильная 40х20", ProductMetal, "м"},
		{"universal.nails_100", "Гвозди строительные, 100 мм", ProductFasteners, "кг"},
		{"universal.screws_wood", "Саморезы по дереву 3.5х35", ProductFasteners, "упак"},
		{"universal.screws_metal", "Саморезы по металлу 4.2х16", ProductFasteners, "упак"},
		{"universal.dowel_6x40", "Дюбель-гвоздь 6х40", ProductFasteners, "упак"},
		{"universal.anchor_10x100", "Анкерный болт 10х100", ProductFasteners, "шт"},
		{"universal.mineral_wool_50", "Утеплитель минеральная вата, 50 мм", ProductInsulation, "упак"},
		{"universal.foam_board_50", "Пенопласт ПСБ-С 25, 50 мм", ProductInsulation, "лист"},
		{"universal.roofing_felt", "Рубероид РКП-350", ProductRoofing, "рулон"},
		{"universal.corrugated_c8", "Профнастил С8 оцинкованный", ProductRoofing, "м²"},
		{"universal.metal_tile", "Металлочерепица", ProductRoofing, "м²"},
		{"universal.porcelain_60", "Керамогранит 60х60", ProductFinishing, "м²"},
		{"universal.wall_tile", "Плитка керамическая настенная", ProductFinishing, "м²"},
		{"universal.laminate_32", "Ламинат, 32 класс", ProductFinishing, "м²"},
		{"universal.linoleum", "Линолеум бытовой", ProductFinishing, "м²"},
		{"universal.cable_vvg", "Кабель ВВГ 3х2.5", ProductElectrical, "м"},
		{"universal.breaker_16a", "Автоматический выключатель 16А", ProductElectrical, "шт"},
		{"universal.socket", "Розетка скрытой установки", ProductElectrical, "шт"},
		{"universal.switch_1", "Выключатель одноклавишный", ProductElectrical, "шт"},
		{"universal.led_lamp_12w", "Лампа светодиодная, 12 Вт", ProductElectrical, "шт"},
		{"universal.ppr_pipe_20", "Труба ППР 20 мм", ProductPlumbing, "м"},
		{"universal.kitchen_mixer", "Смеситель для кухни", ProductPlumbing, "шт"},
		{"universal.toilet_compact", "Унитаз-компакт", ProductPlumbing, "шт"},
		{"universal.interior_door", "Дверь межкомнатная", ProductFinishing, "шт"},
		{"universal.pvc_window", "Окно ПВХ двухкамерное", ProductFinishing, "м²"},
	},

	CategoryPlumbing: {
		{"plumbing.ppr_20", "Труба ППР 20 мм", ProductPlumbing, "м"},
		{"plumbing.ppr_25", "Труба ППР 25 мм", ProductPlumbing, "м"},
		{"plumbing.ppr_32", "Труба ППР 32 мм", ProductPlumbing, "м"},
		{"plumbing.pvc_50", "Труба ПВХ канализационная 50 мм", ProductPlumbing, "м"},
		{"plumbing.pvc_110", "Труба ПВХ канализационная 110 мм", ProductPlumbing, "м"},
		{"plumbing.metalplastic_16", "Труба металлопластиковая 16 мм", ProductPlumbing, "м"},
		{"plumbing.corrugation_toilet", "Гофра для унитаза", ProductPlumbing, "шт"},
		{"plumbing.coupling_20", "Муфта ППР 20 мм", ProductPlumbing, "шт"},
		{"plumbing.elbow_20", "Угольник ППР 90°, 20 мм", ProductPlumbing, "шт"},
		{"plumbing.tee_20", "Тройник ППР 20 мм", ProductPlumbing, "шт"},
		{"plumbing.reducer_25_20", "Переход ППР 25х20", ProductPlumbing, "шт"},
		{"plumbing.union_half", "Американка 1/2\"", ProductPlumbing, "шт"},
		{"plumbing.ball_valve_half", "Кран шаровой 1/2\"", ProductPlumbing, "шт"},
		{"plumbing.ball_valve_three_quarter", "Кран шаровой 3/4\"", ProductPlumbing, "шт"},
		{"plumbing.stop_valve_half", "Вентиль запорный 1/2\"", ProductPlumbing, "шт"},
		{"plumbing.coarse_filter", "Фильтр грубой очистки 1/2\"", ProductPlumbing, "шт"},
		{"plumbing.check_valve", "Обратный клапан 1/2\"", ProductPlumbing, "шт"},
		{"plumbing.pressure_reducer", "Редуктор давления воды", ProductPlumbing, "шт"},
		{"plumbing.water_meter", "Счётчик воды 1/2\"", ProductPlumbing, "шт"},
		{"plumbing.mixer_kitchen", "Смеситель для кухни", ProductPlumbing, "шт"},
		{"plumbing.mixer_basin", "Смеситель для раковины", ProductPlumbing, "шт"},
		{"plumbing.mixer_bath", "Смеситель для ванны с душем", ProductPlumbing, "шт"},
		{"plumbing.shower_set", "Душевая лейка со шлангом", ProductPlumbing, "компл"},
		{"plumbing.shower_rack", "Душевая стойка", ProductPlumbing, "шт"},
		{"plumbing.toilet_compact", "Унитаз-компакт", ProductPlumbing, "шт"},
		{"plumbing.toilet_installation", "Инсталляция для унитаза", ProductPlumbing, "компл"},
		{"plumbing.toilet_seat", "Сиденье для унитаза", ProductPlumbing, "шт"},
		{"plumbing.basin_pedestal", "Раковина-тюльпан", ProductPlumbing, "шт"},
		{"plumbing.basin_counter", "Раковина накладная", ProductPlumbing, "шт"},
		{"plumbing.bath_steel_150", "Ванна стальная 150х70", ProductPlumbing, "шт"},
		{"plumbing.bath_acrylic_170", "Ванна акриловая 170х70", ProductPlumbing, "шт"},
		{"plumbing.shower_tray_90", "Душевой поддон 90х90", ProductPlumbing, "шт"},
		{"plumbing.siphon_basin", "Сифон для раковины", ProductPlumbing, "шт"},
		{"plumbing.siphon_bath", "Сифон для ванны", ProductPlumbing, "шт"},
		{"plumbing.floor_drain_100", "Трап душевой 100х100", ProductPlumbing, "шт"},
		{"plumbing.towel_warmer", "Полотенцесушитель", ProductPlumbing, "шт"},
		{"plumbing.radiator_alu", "Радиатор алюминиевый", ProductPlumbing, "секция"},
		{"plumbing.radiator_bimetal", "Радиатор биметаллический", ProductPlumbing, "секция"},
		{"plumbing.mayevsky_valve", "Кран Маевского", ProductPlumbing, "шт"},
		{"plumbing.boiler_80", "Бойлер накопительный, 80 л", ProductPlumbing, "шт"},
		{"plumbing.gas_heater", "Газовая колонка", ProductPlumbing, "шт"},
		{"plumbing.pump_circulation", "Насос циркуляционный", ProductPlumbing, "шт"},
		{"plumbing.pump_submersible", "Насос погружной", ProductPlumbing, "шт"},
		{"plumbing.hydro_tank_24", "Гидроаккумулятор, 24 л", ProductPlumbing, "шт"},
		{"plumbing.flex_hose_50", "Шланг гибкой подводки 1/2\", 50 см", ProductPlumbing, "шт"},
		{"plumbing.ptfe_tape", "Лента ФУМ", ProductPlumbing, "рулон"},
		{"plumbing.plumbing_flax", "Лён сантехнический", ProductPlumbing, "упак"},
		{"plumbing.sealant_plumbing", "Герметик сантехнический", ProductPlumbing, "туба"},
		{"plumbing.clamp_20", "Хомут металлический 20 мм", ProductFasteners, "шт"},
		{"plumbing.access_hatch", "Люк ревизионный 30х40", ProductPlumbing, "шт"},
	},

	CategoryWood: {
		{"wood.board_25x150", "Доска обрезная 25х150х6000", ProductLumber, "шт"},
		{"wood.beam_100x100", "Брус 100х100х6000", ProductLumber, "шт"},
		{"wood.beam_50x50", "Брус 50х50х3000", ProductLumber, "шт"},
		{"wood.batten_20x40", "Рейка монтажная 20х40", ProductLumber, "м"},
		{"wood.lining_conifer", "Вагонка хвойная", ProductLumber, "м²"},
		{"wood.floorboard_36", "Доска половая, 36 мм", ProductLumber, "м²"},
		{"wood.plywood_fk_10", "Фанера ФК 10 мм, 1525х1525", ProductLumber, "лист"},
		{"wood.osb3_9", "Плита ОСБ-3 9 мм, 1250х2500", ProductLumber, "лист"},
		{"wood.chipboard_16", "ДСП ламинированная, 16 мм", ProductLumber, "лист"},
		{"wood.mdf_panel", "МДФ панель 2600х200", ProductLumber, "шт"},
	},

	CategoryWallpaper: {
		{"wallpaper.paper", "Обои бумажные", ProductFinishing, "рулон"},
		{"wallpaper.vinyl_paper", "Обои виниловые на бумажной основе", ProductFinishing, "рулон"},
		{"wallpaper.vinyl_fleece", "Обои виниловые на флизелиновой основе", ProductFinishing, "рулон"},
		{"wallpaper.fleece_paintable", "Обои флизелиновые под покраску", ProductFinishing, "рулон"},
		{"wallpaper.textile", "Обои текстильные", ProductFinishing, "рулон"},
		{"wallpaper.liquid", "Жидкие обои", ProductFinishing, "упак"},
		{"wallpaper.photo", "Фотообои", ProductFinishing, "компл"},
		{"wallpaper.border", "Бордюр для обоев", ProductFinishing, "рулон"},
		{"wallpaper.glue", "Клей для обоев", ProductMixes, "упак"},
		{"wallpaper.primer", "Грунтовка под обои", ProductMixes, "канистра"},
	},
}

// IsValidCategory reports whether a category code sent by the app is one we actually have a
// template for. the database's CHECK constraint would reject an unknown value anyway, but that
// would surface as a 500 with a postgres error in the log; checking here turns it into a plain
// 400 telling the caller exactly which field is wrong.
func IsValidCategory(code string) bool {
	_, ok := templates[Category(code)]
	return ok
}

// Template returns the rows a newly created shop of this category is seeded with, or nil for an
// unknown category.
//
// the copy is deliberate. a map lookup hands back the slice *header* - a pointer into this package's
// own array - so a caller that assigned to an element (`items[0].Name = ...`) would silently rewrite
// the template for every shop created afterwards in this process. copying makes the returned slice
// the caller's own.
func Template(code string) []Item {
	items, ok := templates[Category(code)]
	if !ok {
		return nil
	}
	out := make([]Item, len(items))
	copy(out, items)
	return out
}

// Size is how many products a shop of this category starts with - what the app shows next to the
// category in the create-shop picker ("Готовый каталог: 50 товаров").
func Size(code string) int {
	return len(templates[Category(code)])
}
