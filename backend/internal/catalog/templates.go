// package catalog holds the ready-made product list a new shop's catalogue is seeded from. every
// shop of a category starts with the same rows differing only in price, which is the only reason
// two shops' baskets can be compared at all.
//
// the lists live in go rather than in a table because nothing joins against them at runtime:
// Shops.Create copies the rows into `products` once, and the copies are what the app reads
// afterwards. a table would cost a migration per edit and buy an admin ui that doesn't exist.
//
// /products.md at the repo root is the human-facing version of the same lists, with the photo each
// row belongs to. edit that, then bring this file into step; templates_test.go pins the counts.
package catalog

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
	// fine, changing its key orphans every shop already seeded with the old one.
	Key  string
	Name string

	// one of the twelve shared codes in categories.go, typed so a typo fails to compile
	Category ProductCategory

	Unit string // шт, кг, мешок ...

	// the photo file inside this category's folder, e.g. "001.jpg" for photos/universal/001.jpg.
	// empty for the templates that have no photo set yet.
	Image string
}

// asserted in templates_test.go, so a hand-edit that drops or duplicates a row fails `go test`
// rather than showing an owner 98 tiles.
const (
	UniversalSize = 100
	PlumbingSize  = 58
	WoodSize      = 10
	WallpaperSize = 10
)

var templates = map[Category][]Item{
	// the real list the founder photographed, transcribed from /products.md. grouped by product
	// category, and that grouping is also the order the owner prices them in - ListProductsByShop
	// sorts template rows by id, and id follows insertion.
	//
	// note what is absent: no cement, blocks, rebar or roofing. this shop sells мелочёвка. the list
	// it replaced had all of those because it was invented rather than observed.
	CategoryUniversal: {
		// инструменты и расходники
		{"universal.tape_45x50", "Скотч упаковочный 4,5х50", ProductTools, "шт", "001.jpg"},
		{"universal.tape_45x40", "Скотч упаковочный 4,5х40", ProductTools, "шт", "002.jpg"},
		{"universal.tape_double_sided_20", "Скотч двухсторонний прозрачный 20 мм х 3 м", ProductTools, "шт", "057.jpg"},
		{"universal.gloves", "Перчатки рабочие (зелёные)", ProductTools, "пара", "007.jpg"},
		{"universal.sandpaper_cloth", "Наждачная бумага на тканевой основе (Россия)", ProductTools, "м", "006.jpg"},
		{"universal.sandpaper_holder", "Держатель для наждачной бумаги 190х90", ProductTools, "шт", "036.jpg"},
		{"universal.grinding_disc_50", "Диск шлифовальный EN-PD-100-50", ProductTools, "шт", "020.jpg"},
		{"universal.grinding_disc_1000", "Диск шлифовальный EN-PD-100-1000", ProductTools, "шт", "021.jpg"},
		{"universal.grinding_disc_1500", "Диск шлифовальный EN-PD-100-1500", ProductTools, "шт", "022.jpg"},
		{"universal.diamond_disc_adp_125", "Диск алмазный 1ADP-EPA-125", ProductTools, "шт", "016.jpg"},
		{"universal.diamond_disc_ads_125", "Диск алмазный 1ADS-EPA-125", ProductTools, "шт", "018.jpg"},
		{"universal.diamond_disc_adm_125", "Диск алмазный 1ADM-EPA-125", ProductTools, "шт", "090.jpg"},
		{"universal.cutting_disc_luga_180", "Диск отрезной LUGA 180", ProductTools, "шт", "017.jpg"},
		{"universal.cutting_disc_epa_125", "Диск отрезной EPA-125", ProductTools, "шт", "019.jpg"},
		{"universal.saw_disc_epa_180", "Диск пильный EPA 1PD-180", ProductTools, "шт", "027.jpg"},
		{"universal.core_bit_25", "Коронка алмазная 25 мм", ProductTools, "шт", "064.jpg"},
		{"universal.core_bit_75", "Коронка алмазная 75 мм", ProductTools, "шт", "065.jpg"},
		{"universal.metal_drill_6", "Сверло по металлу 6 мм", ProductTools, "шт", "010.jpg"},
		{"universal.sds_drill_6x120", "Бур по бетону SDS plus 6х120 Lit", ProductTools, "шт", "025.jpg"},
		{"universal.sds_drill_10x350", "Бур по бетону SDS plus 10х350 Lit", ProductTools, "шт", "026.jpg"},
		{"universal.screwdriver_bit_ph2", "Насадка для шуруповёрта PH2х65", ProductTools, "шт", "009.jpg"},
		{"universal.screwdriver_06x4", "Отвёртка 0,6х4", ProductTools, "шт", "011.jpg"},
		{"universal.spatula_250", "Шпатель 250 мм", ProductTools, "шт", "012.jpg"},
		{"universal.spatula_400", "Шпатель 400 мм", ProductTools, "шт", "013.jpg"},
		{"universal.wrench_10", "Ключ комбинированный 10 мм", ProductTools, "шт", "068.jpg"},
		{"universal.wrench_19", "Ключ комбинированный 19 мм", ProductTools, "шт", "069.jpg"},
		{"universal.hammer_rubber", "Молоток резиновый", ProductTools, "шт", "070.jpg"},
		{"universal.hammer_steel_1kg", "Молоток железный 1 кг Lit", ProductTools, "шт", "071.jpg"},
		{"universal.utility_knife_18", "Нож канцелярский 18 мм", ProductTools, "шт", "024.jpg"},
		{"universal.utility_blades_18", "Лезвия для канцелярского ножа 18 мм, 10 шт", ProductTools, "упак", "023.jpg"},
		{"universal.tape_measure_5m", "Рулетка 5 м Lit", ProductTools, "шт", "028.jpg"},
		{"universal.tape_measure_10m", "Рулетка 10 м Lit", ProductTools, "шт", "029.jpg"},
		{"universal.foam_gun", "Пистолет для монтажной пены", ProductTools, "шт", "034.jpg"},
		{"universal.sealant_gun", "Пистолет для герметика", ProductTools, "шт", "035.jpg"},
		{"universal.builders_line", "Леска строительная", ProductTools, "шт", "091.jpg"},
		{"universal.welding_mask", "Маска сварочная «хамелеон»", ProductTools, "шт", "095.jpg"},
		{"universal.welding_electrodes_3", "Электроды Арсенал 3 мм", ProductTools, "кг", "096.jpg"},

		// электрика
		{"universal.switch_2g_flush", "Выключатель внутренний 2-клавишный (белый)", ProductElectrical, "шт", "031.jpg"},
		{"universal.switch_2g_surface", "Выключатель наружный 2-клавишный (белый)", ProductElectrical, "шт", "030.jpg"},
		{"universal.socket_2g_flush", "Розетка внутренняя 2-местная (белая)", ProductElectrical, "шт", "033.jpg"},
		{"universal.socket_2g_surface", "Розетка наружная 2-местная (белая)", ProductElectrical, "шт", "032.jpg"},
		{"universal.socket_box_ring", "Кольцо-подрозетник", ProductElectrical, "шт", "094.jpg"},
		{"universal.led_lamp_10w", "Лампочка светодиодная 10 Вт", ProductElectrical, "шт", "037.jpg"},
		{"universal.led_lamp_60w", "Лампочка светодиодная 60 Вт", ProductElectrical, "шт", "038.jpg"},
		{"universal.lamp_holder", "Патрон для ламп", ProductElectrical, "шт", "040.jpg"},
		{"universal.led_panel_recessed_square_24w", "LED-панель встраиваемая, квадратная 24 Вт 6500K", ProductElectrical, "шт", "043.jpg"},
		{"universal.led_panel_recessed_round_24w", "LED-панель встраиваемая, круглая 24 Вт 6500K", ProductElectrical, "шт", "044.jpg"},
		{"universal.led_panel_surface_square_24w", "LED-панель накладная, квадратная 24 Вт 6500K", ProductElectrical, "шт", "045.jpg"},
		{"universal.led_panel_surface_round_24w", "LED-панель накладная, круглая 24 Вт 6500K", ProductElectrical, "шт", "042.jpg"},
		{"universal.extension_block_3", "Колодка удлинителя, 3 розетки, без кабеля", ProductElectrical, "шт", "039.jpg"},
		{"universal.plug_16a", "Вилка электрическая турецкая, 16А 250В", ProductElectrical, "шт", "041.jpg"},
		{"universal.cable_pvs_2x15_white", "Кабель медный ПВС 2х1,5, белый", ProductElectrical, "м", "059.jpg"},
		{"universal.cable_pvs_2x15_black", "Кабель медный ПВС 2х1,5, чёрный", ProductElectrical, "м", "060.jpg"},
		{"universal.cable_pvs_2x25_black", "Кабель медный ПВС 2х2,5, чёрный", ProductElectrical, "м", "061.jpg"},
		{"universal.insulating_tape", "Изолента Vini Tape", ProductElectrical, "шт", "058.jpg"},

		// крепёж
		{"universal.screws", "Саморезы", ProductFasteners, "кг", "014.jpg"},
		{"universal.screws_drill_16", "Саморезы «семечки» 1,6 мм", ProductFasteners, "кг", "097.jpg"},
		{"universal.screws_roofing", "Саморезы кровельные", ProductFasteners, "кг", "076.jpg"},
		{"universal.nails", "Гвозди", ProductFasteners, "кг", "015.jpg"},
		{"universal.bolts_galvanized", "Болты оцинкованные", ProductFasteners, "кг", "050.jpg"},
		{"universal.nuts_galvanized", "Гайка оцинкованная", ProductFasteners, "кг", "051.jpg"},
		{"universal.washers_galvanized", "Шайба оцинкованная", ProductFasteners, "кг", "052.jpg"},
		{"universal.anchor_bolt_10x120", "Анкер-болт с гайкой 10х120", ProductFasteners, "шт", "053.jpg"},
		{"universal.anchor_frame_10x112", "Анкер рамный (под отвёртку) 10х112", ProductFasteners, "шт", "054.jpg"},
		{"universal.dowel_6x60", "Дюбель 6х60", ProductFasteners, "шт", "100.jpg"},
		{"universal.dowel_umbrella_10x120", "Дюбель-зонт 10х120 мм", ProductFasteners, "шт", "072.jpg"},
		{"universal.dowel_screw_6x60", "Дюбель-саморез 6х60", ProductFasteners, "кг", "073.jpg"},
		{"universal.dowel_nail", "Дюбель-гвоздь", ProductFasteners, "кг", "074.jpg"},
		{"universal.powder_nails_27", "Дюбель-гвозди для порохового пистолета 27 мм, 200 шт", ProductFasteners, "упак", "075.jpg"},
		{"universal.cable_tie_white_250", "Хомут нейлоновый белый 250 мм, 100 шт", ProductFasteners, "упак", "048.jpg"},
		{"universal.cable_tie_black_250", "Хомут нейлоновый чёрный 250 мм, 100 шт", ProductFasteners, "упак", "049.jpg"},
		{"universal.padlock_70", "Замок навесной 70 мм", ProductFasteners, "шт", "008.jpg"},

		// смеси, клеи и герметики
		{"universal.rotband_25", "Кнауф Ротбанд, 25 кг", ProductMixes, "мешок", "079.jpg"},
		{"universal.fugen_25", "Кнауф Фуген, 25 кг", ProductMixes, "мешок", "084.jpg"},
		{"universal.tile_glue_megamix_22", "Клей плиточный усиленный Megamix 22", ProductMixes, "мешок", "080.jpg"},
		{"universal.putty_eleron_01", "Шпатлёвка Элерон 01 для внутренних работ, 20 кг", ProductMixes, "мешок", "081.jpg"},
		{"universal.putty_eleron_05", "Шпатлёвка гипсовая Элерон 05, 20 кг", ProductMixes, "мешок", "083.jpg"},
		{"universal.putty_eleron_001", "Шпатлёвка суперфинишная Элерон 001", ProductMixes, "мешок", "082.jpg"},
		{"universal.foam_tytan_65", "Пена монтажная универсальная TYTAN 65", ProductMixes, "баллон", "077.jpg"},
		{"universal.silicone_akfix_100e", "Силикон универсальный прозрачный Akfix 100E", ProductMixes, "туба", "098.jpg"},
		{"universal.glue_tytan_classic_fix", "Клей монтажный TYTAN Classic Fix, 310 мл", ProductMixes, "туба", "099.jpg"},
		{"universal.glue_akfix_705", "Клей двухкомпонентный Akfix 705 (большой)", ProductMixes, "компл", "078.jpg"},
		{"universal.pva_eron", "Клей ПВА Эрон", ProductMixes, "кг", "004.jpg"},

		// краски и малярка
		{"universal.enamel_hayat_pf115", "Краска Hayat PF-115 Emali", ProductPaints, "кг", "005.jpg"},
		{"universal.tint_palizh", "Колер Palizh", ProductPaints, "шт", "066.jpg"},
		{"universal.tint_pufamix", "Колер PUFAMIX, оригинал", ProductPaints, "шт", "067.jpg"},
		{"universal.solvent_646", "Растворитель Б-646", ProductPaints, "л", "055.jpg"},
		{"universal.thinner", "Разбавитель", ProductPaints, "л", "056.jpg"},
		{"universal.brush_3", "Кисть для водоэмульсионных красок 3\"", ProductPaints, "шт", "046.jpg"},
		{"universal.brush_4", "Кисть для водоэмульсионных красок 4\"", ProductPaints, "шт", "047.jpg"},
		{"universal.masking_film_180", "Плёнка защитная с малярным скотчем, 180 см", ProductPaints, "рулон", "003.jpg"},

		// отделка
		{"universal.drywall_wall", "Гипсокартон стеновой", ProductFinishing, "лист", "085.jpg"},
		{"universal.drywall_ceiling", "Гипсокартон потолочный", ProductFinishing, "лист", "086.jpg"},
		{"universal.drywall_moisture", "Гипсокартон стеновой влагостойкий", ProductFinishing, "лист", "087.jpg"},
		{"universal.tile_leveling_clip_14", "СВП зажим 1,4 мм, 250 шт", ProductFinishing, "упак", "062.jpg"},
		{"universal.tile_leveling_wedge_14", "СВП клин 1,4 мм, 100 шт", ProductFinishing, "упак", "063.jpg"},

		// изоляция
		{"universal.roll_insulation_03", "Изоляция рулонная (синтепон), завод 03", ProductInsulation, "рулон", "088.jpg"},
		{"universal.roll_insulation_05", "Изоляция рулонная (синтепон), завод 05", ProductInsulation, "рулон", "089.jpg"},
		{"universal.film_black_06", "Плёнка полиэтиленовая 0,6, чёрная", ProductInsulation, "м", "092.jpg"},
		{"universal.film_white_06", "Плёнка полиэтиленовая 0,6, белая", ProductInsulation, "м", "093.jpg"},
	},

	// the founder's own сантехника supplier list, 58 VERO PPR fittings, transcribed from
	// /products.md and photographed one per row. it replaced an invented 50-item list that ran from
	// труба ППР to газовая колонка - a plausible-looking catalogue nobody actually stocks as one.
	//
	// what a real fittings shop turns out to be: муфты, отводы, тройники, краны and the adapters
	// between them, in two pipe sizes (20 and 25 мм) and two thread genders. В/Р is внутренняя
	// резьба (female), Н/Р наружная (male) - the distinction is half of why there are 58 rows and
	// not 20.
	//
	// the brand stays in the name on the founder's call: these are the parts the shop sells, and
	// the photo carries the VERO logo either way. it does mean a shop stocking another PPR brand
	// prices a VERO label, since a template row's name is locked.
	//
	// every row is ProductPlumbing, клипсы and хомуты included. they fasten things, but a customer
	// tapping «Крепёж» on the home grid is after дюбели and саморезы, not a saddle clip sized to
	// 20 мм PPR pipe. this deliberately drops the old list's lone ProductFasteners row.
	CategoryPlumbing: {
		{"plumbing.adapter_coupling_female_20", "VERO Адаптер-муфта комб. В/Р 20х1/2", ProductPlumbing, "шт", "001.jpg"},
		{"plumbing.adapter_coupling_female_25", "VERO Адаптер-муфта комб. В/Р 25х1/2", ProductPlumbing, "шт", "002.jpg"},
		{"plumbing.adapter_coupling_male_20", "VERO Адаптер-муфта комб. Н/Р 20х1/2", ProductPlumbing, "шт", "003.jpg"},
		{"plumbing.adapter_coupling_male_25", "VERO Адаптер-муфта комб. Н/Р 25х1/2", ProductPlumbing, "шт", "004.jpg"},
		{"plumbing.adapter_union_nut_25_half", "VERO Адаптер с накидной гайкой 25х1/2 (V-2)", ProductPlumbing, "шт", "005.jpg"},
		{"plumbing.adapter_union_nut_25_three_quarter", "VERO Адаптер с накидной гайкой 25х3/4 (V-2)", ProductPlumbing, "шт", "006.jpg"},
		{"plumbing.adapter_nipple_25_half", "VERO Адаптер с накидной гайкой (ниппель) 25х1/2", ProductPlumbing, "шт", "007.jpg"},
		{"plumbing.double_elbow_bracket_female_20", "VERO Двойной отвод с креплением В/Р 20х15", ProductPlumbing, "шт", "008.jpg"},
		{"plumbing.double_elbow_bracket_male_20", "VERO Двойной отвод с креплением Н/Р 20х15", ProductPlumbing, "шт", "009.jpg"},
		{"plumbing.plug_20", "VERO Заглушка 20", ProductPlumbing, "шт", "010.jpg"},
		{"plumbing.plug_25", "VERO Заглушка 25", ProductPlumbing, "шт", "011.jpg"},
		{"plumbing.clip_20", "VERO Клипса 20", ProductPlumbing, "шт", "012.jpg"},
		{"plumbing.clip_25", "VERO Клипса 25", ProductPlumbing, "шт", "013.jpg"},
		{"plumbing.radiator_valve_straight_20", "VERO Кран для радиатора прямой 20х1/2", ProductPlumbing, "шт", "014.jpg"},
		{"plumbing.cross_90_20", "VERO Крестовина 90° 20", ProductPlumbing, "шт", "015.jpg"},
		{"plumbing.clamp_metal_20_24", "VERO Хомут металлический 20-24 (1/2\")", ProductPlumbing, "шт", "016.jpg"},
		{"plumbing.clamp_metal_45_52", "VERO Хомут металлический 45-52 (1 1/2\")", ProductPlumbing, "шт", "017.jpg"},
		{"plumbing.coupling_20", "VERO Муфта 20", ProductPlumbing, "шт", "018.jpg"},
		{"plumbing.coupling_25", "VERO Муфта 25", ProductPlumbing, "шт", "019.jpg"},
		{"plumbing.bypass_20", "VERO Обвод 20", ProductPlumbing, "шт", "020.jpg"},
		{"plumbing.bypass_25", "VERO Обвод 25", ProductPlumbing, "шт", "021.jpg"},
		{"plumbing.elbow_90_20", "VERO Отвод 90° 20", ProductPlumbing, "шт", "022.jpg"},
		{"plumbing.elbow_90_25", "VERO Отвод 90° 25", ProductPlumbing, "шт", "023.jpg"},
		{"plumbing.elbow_wall_female_20", "VERO Отвод с настенным креплением В/Р 20", ProductPlumbing, "шт", "024.jpg"},
		{"plumbing.elbow_wall_female_25", "VERO Отвод с настенным креплением В/Р 25", ProductPlumbing, "шт", "025.jpg"},
		{"plumbing.elbow_wall_male_20", "VERO Отвод с настенным креплением Н/Р 20", ProductPlumbing, "шт", "026.jpg"},
		{"plumbing.elbow_wall_male_25", "VERO Отвод с настенным креплением Н/Р 25", ProductPlumbing, "шт", "027.jpg"},
		{"plumbing.reducer_25_20", "VERO Переходник 25-20", ProductPlumbing, "шт", "028.jpg"},
		{"plumbing.reducer_32_20", "VERO Переходник 32-20", ProductPlumbing, "шт", "029.jpg"},
		{"plumbing.elbow_45_20", "VERO Полуотвод 20", ProductPlumbing, "шт", "030.jpg"},
		{"plumbing.elbow_45_25", "VERO Полуотвод 25", ProductPlumbing, "шт", "031.jpg"},
		{"plumbing.union_female_20_half", "VERO Ракор В/Р 20х1/2", ProductPlumbing, "шт", "032.jpg"},
		{"plumbing.union_female_25_half", "VERO Ракор В/Р 25х1/2", ProductPlumbing, "шт", "033.jpg"},
		{"plumbing.union_female_25_three_quarter", "VERO Ракор В/Р 25х3/4", ProductPlumbing, "шт", "034.jpg"},
		{"plumbing.union_male_20_half", "VERO Ракор Н/Р 20х1/2", ProductPlumbing, "шт", "035.jpg"},
		{"plumbing.union_male_25_half", "VERO Ракор Н/Р 25х1/2", ProductPlumbing, "шт", "036.jpg"},
		{"plumbing.tee_20", "VERO Тройник 20", ProductPlumbing, "шт", "037.jpg"},
		{"plumbing.tee_25", "VERO Тройник 25", ProductPlumbing, "шт", "038.jpg"},
		{"plumbing.tee_female_20_half", "VERO Тройник комб. с В/Р 20х1/2", ProductPlumbing, "шт", "039.jpg"},
		{"plumbing.tee_female_25_half", "VERO Тройник комб. с В/Р 25х1/2", ProductPlumbing, "шт", "040.jpg"},
		{"plumbing.tee_male_20_half", "VERO Тройник комб. с Н/Р 20х1/2", ProductPlumbing, "шт", "041.jpg"},
		{"plumbing.tee_male_25_half", "VERO Тройник комб. с Н/Р 25х1/2", ProductPlumbing, "шт", "042.jpg"},
		{"plumbing.tee_reducing_25_20_25", "VERO Тройник переходник 25-20-25", ProductPlumbing, "шт", "043.jpg"},
		{"plumbing.tee_reducing_32_20_32", "VERO Тройник переходник 32-20-32", ProductPlumbing, "шт", "044.jpg"},
		{"plumbing.radiator_valve_angle_20", "VERO Угловой кран для радиатора 20х1/2", ProductPlumbing, "шт", "045.jpg"},
		{"plumbing.radiator_valve_angle_20_import", "VERO Угловой кран для радиатора 20х1/2 (импорт)", ProductPlumbing, "шт", "046.jpg"},
		{"plumbing.elbow_female_20_half", "VERO Угол В/Р 20х1/2", ProductPlumbing, "шт", "047.jpg"},
		{"plumbing.elbow_female_25_half", "VERO Угол В/Р 25х1/2", ProductPlumbing, "шт", "048.jpg"},
		{"plumbing.elbow_male_20_half", "VERO Угол Н/Р 20х1/2", ProductPlumbing, "шт", "049.jpg"},
		{"plumbing.elbow_male_25_half", "VERO Угол Н/Р 25х1/2", ProductPlumbing, "шт", "050.jpg"},
		{"plumbing.elbow_nipple_20_half", "VERO Угол с накидной гайкой (ниппель) 20х1/2", ProductPlumbing, "шт", "051.jpg"},
		{"plumbing.elbow_nipple_25_three_quarter", "VERO Угол с накидной гайкой (ниппель) 25х3/4", ProductPlumbing, "шт", "052.jpg"},
		{"plumbing.filter_20_brass", "VERO Фильтр 20 «мама» (латунь)", ProductPlumbing, "шт", "053.jpg"},
		{"plumbing.filter_25_brass", "VERO Фильтр 25 «мама» (латунь)", ProductPlumbing, "шт", "054.jpg"},
		{"plumbing.ball_valve_20", "VERO Шаровой кран 20", ProductPlumbing, "шт", "055.jpg"},
		{"plumbing.ball_valve_25", "VERO Шаровой кран 25", ProductPlumbing, "шт", "056.jpg"},
		{"plumbing.ball_valve_20_eco", "VERO Шаровой кран 20 ECO", ProductPlumbing, "шт", "057.jpg"},
		{"plumbing.ball_valve_25_eco", "VERO Шаровой кран 25 ECO", ProductPlumbing, "шт", "058.jpg"},
	},

	CategoryWood: {
		{"wood.board_25x150", "Доска обрезная 25х150х6000", ProductLumber, "шт", ""},
		{"wood.beam_100x100", "Брус 100х100х6000", ProductLumber, "шт", ""},
		{"wood.beam_50x50", "Брус 50х50х3000", ProductLumber, "шт", ""},
		{"wood.batten_20x40", "Рейка монтажная 20х40", ProductLumber, "м", ""},
		{"wood.lining_conifer", "Вагонка хвойная", ProductLumber, "м²", ""},
		{"wood.floorboard_36", "Доска половая, 36 мм", ProductLumber, "м²", ""},
		{"wood.plywood_fk_10", "Фанера ФК 10 мм, 1525х1525", ProductLumber, "лист", ""},
		{"wood.osb3_9", "Плита ОСБ-3 9 мм, 1250х2500", ProductLumber, "лист", ""},
		{"wood.chipboard_16", "ДСП ламинированная, 16 мм", ProductLumber, "лист", ""},
		{"wood.mdf_panel", "МДФ панель 2600х200", ProductLumber, "шт", ""},
	},

	// обои are ten *slots*, not ten products.
	//
	// two wallpaper shops across the road stock almost nothing in common - different suppliers,
	// different collections, different articles - so a template of ten named rolls would be ten
	// rolls nine of which the shop does not carry. every owner would leave them unpriced and the
	// обои basket index would be built entirely out of imputed market rates.
	//
	// a slot instead fixes the two things that make wallpaper comparable, its class and its country,
	// and leaves the product to the owner. the index then compares "premium russian wallpaper here"
	// against "premium russian wallpaper there" - different rolls, fair question. the founder's
	// split: 3 премиум (one per country) + 4 стандарт (2 UZ, 2 RU) + 3 эконом (1 UZ, 2 CN).
	//
	// the names below are placeholders saying what belongs in the slot. see ownerNamedCategories.
	CategoryWallpaper: {
		{"wallpaper.premium_ru", "Обои премиум (Россия)", ProductFinishing, "рулон", ""},
		{"wallpaper.premium_cn", "Обои премиум (Китай)", ProductFinishing, "рулон", ""},
		{"wallpaper.premium_uz", "Обои премиум (Узбекистан)", ProductFinishing, "рулон", ""},
		{"wallpaper.standard_uz_1", "Обои стандарт (Узбекистан) №1", ProductFinishing, "рулон", ""},
		{"wallpaper.standard_uz_2", "Обои стандарт (Узбекистан) №2", ProductFinishing, "рулон", ""},
		{"wallpaper.standard_ru_1", "Обои стандарт (Россия) №1", ProductFinishing, "рулон", ""},
		{"wallpaper.standard_ru_2", "Обои стандарт (Россия) №2", ProductFinishing, "рулон", ""},
		{"wallpaper.econom_uz", "Обои эконом (Узбекистан)", ProductFinishing, "рулон", ""},
		{"wallpaper.econom_cn_1", "Обои эконом (Китай) №1", ProductFinishing, "рулон", ""},
		{"wallpaper.econom_cn_2", "Обои эконом (Китай) №2", ProductFinishing, "рулон", ""},
	},
}

// the categories whose template is a set of slots rather than a set of products. declared as
// categories, not as a hand-written list of keys: a key list would be a second copy of "which rows
// are slots" that can drift from the template describing them.
var ownerNamedCategories = []Category{CategoryWallpaper}

var ownerNamedKeys = func() map[string]bool {
	set := make(map[string]bool)
	for _, category := range ownerNamedCategories {
		for _, item := range templates[category] {
			set[item.Key] = true
		}
	}
	return set
}()

// IsOwnerNamedSlot reports whether this template key names a slot the owner fills in rather than a
// product the template names for them. asked of the key rather than of the shop's category, because
// the handler already holds the product row and would otherwise need a second query.
func IsOwnerNamedSlot(templateKey string) bool {
	return ownerNamedKeys[templateKey]
}

// ImagePath is what goes into products.image_path: the photo's location inside the served images
// folder, e.g. "universal/001.jpg". empty for an item with no photo.
//
// the category is passed in rather than parsed off the key prefix, because the seeder already knows
// which category it is copying and guessing from a string would tie the folder layout to the naming
// convention of the keys.
func (i Item) ImagePath(category Category) string {
	if i.Image == "" {
		return ""
	}
	return string(category) + "/" + i.Image
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
	_, ok := templates[Category(code)]
	return ok
}

// Template returns the rows a new shop of this category is seeded with, or nil for an unknown one.
//
// the copy is deliberate: a map lookup hands back the slice header, so a caller assigning to an
// element would rewrite the template for every shop created afterwards in this process.
func Template(code string) []Item {
	items, ok := templates[Category(code)]
	if !ok {
		return nil
	}
	out := make([]Item, len(items))
	copy(out, items)
	return out
}

// Size is how many products a shop of this category starts with - the "Готовый каталог: 100 товаров"
// hint in the create-shop picker.
func Size(code string) int {
	return len(templates[Category(code)])
}
