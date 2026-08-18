# Шаблоны товаров

Списки, которыми заполняется каталог магазина сразу после создания.
Код: `backend/internal/catalog/templates.go`. Фото: `photos/<категория>/NNN.jpg`.

**Как добавить товар:** положить фото в `photos/<категория>/NNN.jpg` под следующим свободным номером →
добавить строку в таблицу ниже → сказать Claude «обнови шаблоны». Ключ придумает он.

**Два правила:** ключ (`template_key`) не меняется никогда — по нему товары сравниваются между
магазинами. Единица измерения фиксирует количество: «кг», а не «мешок», если вес не написан в
названии, иначе цены перестают быть сравнимыми.

Изменения касаются только новых магазинов — шаблон копируется один раз, при создании.

---

## Универсальный — 100 товаров

### Инструменты и расходники · `tools` — 37

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 001 | Скотч упаковочный 4,5х50 | шт | `universal.tape_45x50` |
| 002 | Скотч упаковочный 4,5х40 | шт | `universal.tape_45x40` |
| 057 | Скотч двухсторонний прозрачный 20 мм х 3 м | шт | `universal.tape_double_sided_20` |
| 007 | Перчатки рабочие (зелёные) | пара | `universal.gloves` |
| 006 | Наждачная бумага на тканевой основе (Россия) | м | `universal.sandpaper_cloth` |
| 036 | Держатель для наждачной бумаги 190х90 | шт | `universal.sandpaper_holder` |
| 020 | Диск шлифовальный EN-PD-100-50 | шт | `universal.grinding_disc_50` |
| 021 | Диск шлифовальный EN-PD-100-1000 | шт | `universal.grinding_disc_1000` |
| 022 | Диск шлифовальный EN-PD-100-1500 | шт | `universal.grinding_disc_1500` |
| 016 | Диск алмазный 1ADP-EPA-125 | шт | `universal.diamond_disc_adp_125` |
| 018 | Диск алмазный 1ADS-EPA-125 | шт | `universal.diamond_disc_ads_125` |
| 090 | Диск алмазный 1ADM-EPA-125 | шт | `universal.diamond_disc_adm_125` |
| 017 | Диск отрезной LUGA 180 | шт | `universal.cutting_disc_luga_180` |
| 019 | Диск отрезной EPA-125 | шт | `universal.cutting_disc_epa_125` |
| 027 | Диск пильный EPA 1PD-180 | шт | `universal.saw_disc_epa_180` |
| 064 | Коронка алмазная 25 мм | шт | `universal.core_bit_25` |
| 065 | Коронка алмазная 75 мм | шт | `universal.core_bit_75` |
| 010 | Сверло по металлу 6 мм | шт | `universal.metal_drill_6` |
| 025 | Бур по бетону SDS plus 6х120 Lit | шт | `universal.sds_drill_6x120` |
| 026 | Бур по бетону SDS plus 10х350 Lit | шт | `universal.sds_drill_10x350` |
| 009 | Насадка для шуруповёрта PH2х65 | шт | `universal.screwdriver_bit_ph2` |
| 011 | Отвёртка 0,6х4 | шт | `universal.screwdriver_06x4` |
| 012 | Шпатель 250 мм | шт | `universal.spatula_250` |
| 013 | Шпатель 400 мм | шт | `universal.spatula_400` |
| 068 | Ключ комбинированный 10 мм | шт | `universal.wrench_10` |
| 069 | Ключ комбинированный 19 мм | шт | `universal.wrench_19` |
| 070 | Молоток резиновый | шт | `universal.hammer_rubber` |
| 071 | Молоток железный 1 кг Lit | шт | `universal.hammer_steel_1kg` |
| 024 | Нож канцелярский 18 мм | шт | `universal.utility_knife_18` |
| 023 | Лезвия для канцелярского ножа 18 мм, 10 шт | упак | `universal.utility_blades_18` |
| 028 | Рулетка 5 м Lit | шт | `universal.tape_measure_5m` |
| 029 | Рулетка 10 м Lit | шт | `universal.tape_measure_10m` |
| 034 | Пистолет для монтажной пены | шт | `universal.foam_gun` |
| 035 | Пистолет для герметика | шт | `universal.sealant_gun` |
| 091 | Леска строительная | шт | `universal.builders_line` |
| 095 | Маска сварочная «хамелеон» | шт | `universal.welding_mask` |
| 096 | Электроды Арсенал 3 мм | кг | `universal.welding_electrodes_3` |

### Электрика · `electrical` — 18

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 031 | Выключатель внутренний 2-клавишный (белый) | шт | `universal.switch_2g_flush` |
| 030 | Выключатель наружный 2-клавишный (белый) | шт | `universal.switch_2g_surface` |
| 033 | Розетка внутренняя 2-местная (белая) | шт | `universal.socket_2g_flush` |
| 032 | Розетка наружная 2-местная (белая) | шт | `universal.socket_2g_surface` |
| 094 | Кольцо-подрозетник | шт | `universal.socket_box_ring` |
| 037 | Лампочка светодиодная 10 Вт | шт | `universal.led_lamp_10w` |
| 038 | Лампочка светодиодная 60 Вт | шт | `universal.led_lamp_60w` |
| 040 | Патрон для ламп | шт | `universal.lamp_holder` |
| 043 | LED-панель встраиваемая, квадратная 24 Вт 6500K | шт | `universal.led_panel_recessed_square_24w` |
| 044 | LED-панель встраиваемая, круглая 24 Вт 6500K | шт | `universal.led_panel_recessed_round_24w` |
| 045 | LED-панель накладная, квадратная 24 Вт 6500K | шт | `universal.led_panel_surface_square_24w` |
| 042 | LED-панель накладная, круглая 24 Вт 6500K | шт | `universal.led_panel_surface_round_24w` |
| 039 | Колодка удлинителя, 3 розетки, без кабеля | шт | `universal.extension_block_3` |
| 041 | Вилка электрическая турецкая, 16А 250В | шт | `universal.plug_16a` |
| 059 | Кабель медный ПВС 2х1,5, белый | м | `universal.cable_pvs_2x15_white` |
| 060 | Кабель медный ПВС 2х1,5, чёрный | м | `universal.cable_pvs_2x15_black` |
| 061 | Кабель медный ПВС 2х2,5, чёрный | м | `universal.cable_pvs_2x25_black` |
| 058 | Изолента Vini Tape | шт | `universal.insulating_tape` |

### Крепёж · `fasteners` — 17

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 014 | Саморезы | кг | `universal.screws` |
| 097 | Саморезы «семечки» 1,6 мм | кг | `universal.screws_drill_16` |
| 076 | Саморезы кровельные | кг | `universal.screws_roofing` |
| 015 | Гвозди | кг | `universal.nails` |
| 050 | Болты оцинкованные | кг | `universal.bolts_galvanized` |
| 051 | Гайка оцинкованная | кг | `universal.nuts_galvanized` |
| 052 | Шайба оцинкованная | кг | `universal.washers_galvanized` |
| 053 | Анкер-болт с гайкой 10х120 | шт | `universal.anchor_bolt_10x120` |
| 054 | Анкер рамный (под отвёртку) 10х112 | шт | `universal.anchor_frame_10x112` |
| 100 | Дюбель 6х60 | шт | `universal.dowel_6x60` |
| 072 | Дюбель-зонт 10х120 мм | шт | `universal.dowel_umbrella_10x120` |
| 073 | Дюбель-саморез 6х60 | кг | `universal.dowel_screw_6x60` |
| 074 | Дюбель-гвоздь | кг | `universal.dowel_nail` |
| 075 | Дюбель-гвозди для порохового пистолета 27 мм, 200 шт | упак | `universal.powder_nails_27` |
| 048 | Хомут нейлоновый белый 250 мм, 100 шт | упак | `universal.cable_tie_white_250` |
| 049 | Хомут нейлоновый чёрный 250 мм, 100 шт | упак | `universal.cable_tie_black_250` |
| 008 | Замок навесной 70 мм | шт | `universal.padlock_70` |

### Смеси, клеи и герметики · `mixes` — 11

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 079 | Кнауф Ротбанд, 25 кг | мешок | `universal.rotband_25` |
| 084 | Кнауф Фуген, 25 кг | мешок | `universal.fugen_25` |
| 080 | Клей плиточный усиленный Megamix 22 | мешок | `universal.tile_glue_megamix_22` |
| 081 | Шпатлёвка Элерон 01 для внутренних работ, 20 кг | мешок | `universal.putty_eleron_01` |
| 083 | Шпатлёвка гипсовая Элерон 05, 20 кг | мешок | `universal.putty_eleron_05` |
| 082 | Шпатлёвка суперфинишная Элерон 001 | мешок | `universal.putty_eleron_001` |
| 077 | Пена монтажная универсальная TYTAN 65 | баллон | `universal.foam_tytan_65` |
| 098 | Силикон универсальный прозрачный Akfix 100E | туба | `universal.silicone_akfix_100e` |
| 099 | Клей монтажный TYTAN Classic Fix, 310 мл | туба | `universal.glue_tytan_classic_fix` |
| 078 | Клей двухкомпонентный Akfix 705 (большой) | компл | `universal.glue_akfix_705` |
| 004 | Клей ПВА Эрон | кг | `universal.pva_eron` |

### Краски и малярка · `paints` — 8

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 005 | Краска Hayat PF-115 Emali | кг | `universal.enamel_hayat_pf115` |
| 066 | Колер Palizh | шт | `universal.tint_palizh` |
| 067 | Колер PUFAMIX, оригинал | шт | `universal.tint_pufamix` |
| 055 | Растворитель Б-646 | л | `universal.solvent_646` |
| 056 | Разбавитель | л | `universal.thinner` |
| 046 | Кисть для водоэмульсионных красок 3" | шт | `universal.brush_3` |
| 047 | Кисть для водоэмульсионных красок 4" | шт | `universal.brush_4` |
| 003 | Плёнка защитная с малярным скотчем, 180 см | рулон | `universal.masking_film_180` |

### Отделка · `finishing` — 5

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 085 | Гипсокартон стеновой | лист | `universal.drywall_wall` |
| 086 | Гипсокартон потолочный | лист | `universal.drywall_ceiling` |
| 087 | Гипсокартон стеновой влагостойкий | лист | `universal.drywall_moisture` |
| 062 | СВП зажим 1,4 мм, 250 шт | упак | `universal.tile_leveling_clip_14` |
| 063 | СВП клин 1,4 мм, 100 шт | упак | `universal.tile_leveling_wedge_14` |

### Изоляция · `insulation` — 4

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 088 | Изоляция рулонная (синтепон), завод 03 | рулон | `universal.roll_insulation_03` |
| 089 | Изоляция рулонная (синтепон), завод 05 | рулон | `universal.roll_insulation_05` |
| 092 | Плёнка полиэтиленовая 0,6, чёрная | м | `universal.film_black_06` |
| 093 | Плёнка полиэтиленовая 0,6, белая | м | `universal.film_white_06` |

---

## Обои — 10 мест

У обоев нет общего списка товаров: ассортимент двух соседних магазинов не пересекается почти нигде.
Поэтому шаблон обоев — это **места под товары**. Место задаёт класс и страну, товар вписывает
владелец. Сравниваются места: «премиум Россия» здесь против «премиум Россия» там.

| # | Место | Ключ |
| --- | --- | --- |
| 1 | Обои премиум (Россия) | `wallpaper.premium_ru` |
| 2 | Обои премиум (Китай) | `wallpaper.premium_cn` |
| 3 | Обои премиум (Узбекистан) | `wallpaper.premium_uz` |
| 4 | Обои стандарт (Узбекистан) №1 | `wallpaper.standard_uz_1` |
| 5 | Обои стандарт (Узбекистан) №2 | `wallpaper.standard_uz_2` |
| 6 | Обои стандарт (Россия) №1 | `wallpaper.standard_ru_1` |
| 7 | Обои стандарт (Россия) №2 | `wallpaper.standard_ru_2` |
| 8 | Обои эконом (Узбекистан) | `wallpaper.econom_uz` |
| 9 | Обои эконом (Китай) №1 | `wallpaper.econom_cn_1` |
| 10 | Обои эконом (Китай) №2 | `wallpaper.econom_cn_2` |

3 премиум (по одному на страну) + 4 стандарт (2 УЗ + 2 РФ) + 3 эконом (1 УЗ + 2 КНР).
Все — категория `finishing`, единица **рулон**.

Владелец меняет название, цену и наличие. Категорию, единицу и само место — нет: единица держит
сравнение «за рулон», а удаление дорогих мест сделало бы магазин «дешёвым» без снижения цен.

Фото у мест нет — товар в каждом магазине свой.

---

## Сантехника — 58 товаров

Каталог фитингов VERO — то, чем шкаф сантехнического магазина занят на самом деле: муфты, отводы,
тройники, краны и переходники между ними. Всё — категория `plumbing`, единица **шт**, одна
фотография на позицию.

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 001 | VERO Адаптер-муфта комб. В/Р 20х1/2 | шт | `plumbing.adapter_coupling_female_20` |
| 002 | VERO Адаптер-муфта комб. В/Р 25х1/2 | шт | `plumbing.adapter_coupling_female_25` |
| 003 | VERO Адаптер-муфта комб. Н/Р 20х1/2 | шт | `plumbing.adapter_coupling_male_20` |
| 004 | VERO Адаптер-муфта комб. Н/Р 25х1/2 | шт | `plumbing.adapter_coupling_male_25` |
| 005 | VERO Адаптер с накидной гайкой 25х1/2 (V-2) | шт | `plumbing.adapter_union_nut_25_half` |
| 006 | VERO Адаптер с накидной гайкой 25х3/4 (V-2) | шт | `plumbing.adapter_union_nut_25_three_quarter` |
| 007 | VERO Адаптер с накидной гайкой (ниппель) 25х1/2 | шт | `plumbing.adapter_nipple_25_half` |
| 008 | VERO Двойной отвод с креплением В/Р 20х15 | шт | `plumbing.double_elbow_bracket_female_20` |
| 009 | VERO Двойной отвод с креплением Н/Р 20х15 | шт | `plumbing.double_elbow_bracket_male_20` |
| 010 | VERO Заглушка 20 | шт | `plumbing.plug_20` |
| 011 | VERO Заглушка 25 | шт | `plumbing.plug_25` |
| 012 | VERO Клипса 20 | шт | `plumbing.clip_20` |
| 013 | VERO Клипса 25 | шт | `plumbing.clip_25` |
| 014 | VERO Кран для радиатора прямой 20х1/2 | шт | `plumbing.radiator_valve_straight_20` |
| 015 | VERO Крестовина 90° 20 | шт | `plumbing.cross_90_20` |
| 016 | VERO Хомут металлический 20-24 (1/2") | шт | `plumbing.clamp_metal_20_24` |
| 017 | VERO Хомут металлический 45-52 (1 1/2") | шт | `plumbing.clamp_metal_45_52` |
| 018 | VERO Муфта 20 | шт | `plumbing.coupling_20` |
| 019 | VERO Муфта 25 | шт | `plumbing.coupling_25` |
| 020 | VERO Обвод 20 | шт | `plumbing.bypass_20` |
| 021 | VERO Обвод 25 | шт | `plumbing.bypass_25` |
| 022 | VERO Отвод 90° 20 | шт | `plumbing.elbow_90_20` |
| 023 | VERO Отвод 90° 25 | шт | `plumbing.elbow_90_25` |
| 024 | VERO Отвод с настенным креплением В/Р 20 | шт | `plumbing.elbow_wall_female_20` |
| 025 | VERO Отвод с настенным креплением В/Р 25 | шт | `plumbing.elbow_wall_female_25` |
| 026 | VERO Отвод с настенным креплением Н/Р 20 | шт | `plumbing.elbow_wall_male_20` |
| 027 | VERO Отвод с настенным креплением Н/Р 25 | шт | `plumbing.elbow_wall_male_25` |
| 028 | VERO Переходник 25-20 | шт | `plumbing.reducer_25_20` |
| 029 | VERO Переходник 32-20 | шт | `plumbing.reducer_32_20` |
| 030 | VERO Полуотвод 20 | шт | `plumbing.elbow_45_20` |
| 031 | VERO Полуотвод 25 | шт | `plumbing.elbow_45_25` |
| 032 | VERO Ракор В/Р 20х1/2 | шт | `plumbing.union_female_20_half` |
| 033 | VERO Ракор В/Р 25х1/2 | шт | `plumbing.union_female_25_half` |
| 034 | VERO Ракор В/Р 25х3/4 | шт | `plumbing.union_female_25_three_quarter` |
| 035 | VERO Ракор Н/Р 20х1/2 | шт | `plumbing.union_male_20_half` |
| 036 | VERO Ракор Н/Р 25х1/2 | шт | `plumbing.union_male_25_half` |
| 037 | VERO Тройник 20 | шт | `plumbing.tee_20` |
| 038 | VERO Тройник 25 | шт | `plumbing.tee_25` |
| 039 | VERO Тройник комб. с В/Р 20х1/2 | шт | `plumbing.tee_female_20_half` |
| 040 | VERO Тройник комб. с В/Р 25х1/2 | шт | `plumbing.tee_female_25_half` |
| 041 | VERO Тройник комб. с Н/Р 20х1/2 | шт | `plumbing.tee_male_20_half` |
| 042 | VERO Тройник комб. с Н/Р 25х1/2 | шт | `plumbing.tee_male_25_half` |
| 043 | VERO Тройник переходник 25-20-25 | шт | `plumbing.tee_reducing_25_20_25` |
| 044 | VERO Тройник переходник 32-20-32 | шт | `plumbing.tee_reducing_32_20_32` |
| 045 | VERO Угловой кран для радиатора 20х1/2 | шт | `plumbing.radiator_valve_angle_20` |
| 046 | VERO Угловой кран для радиатора 20х1/2 (импорт) | шт | `plumbing.radiator_valve_angle_20_import` |
| 047 | VERO Угол В/Р 20х1/2 | шт | `plumbing.elbow_female_20_half` |
| 048 | VERO Угол В/Р 25х1/2 | шт | `plumbing.elbow_female_25_half` |
| 049 | VERO Угол Н/Р 20х1/2 | шт | `plumbing.elbow_male_20_half` |
| 050 | VERO Угол Н/Р 25х1/2 | шт | `plumbing.elbow_male_25_half` |
| 051 | VERO Угол с накидной гайкой (ниппель) 20х1/2 | шт | `plumbing.elbow_nipple_20_half` |
| 052 | VERO Угол с накидной гайкой (ниппель) 25х3/4 | шт | `plumbing.elbow_nipple_25_three_quarter` |
| 053 | VERO Фильтр 20 «мама» (латунь) | шт | `plumbing.filter_20_brass` |
| 054 | VERO Фильтр 25 «мама» (латунь) | шт | `plumbing.filter_25_brass` |
| 055 | VERO Шаровой кран 20 | шт | `plumbing.ball_valve_20` |
| 056 | VERO Шаровой кран 25 | шт | `plumbing.ball_valve_25` |
| 057 | VERO Шаровой кран 20 ECO | шт | `plumbing.ball_valve_20_eco` |
| 058 | VERO Шаровой кран 25 ECO | шт | `plumbing.ball_valve_25_eco` |

Хомуты и клипсы (016, 017, 012, 013) — тоже `plumbing`, а не `fasteners`: они крепят, но покупатель,
который жмёт «Крепёж» на главной, ищет дюбели и саморезы, а не клипсу под 20-ю трубу.

Фотографии 001/002 и 012/013 совпадают попиксельно — тот же кадр на два диаметра. Строки при этом
разные, каждая со своим файлом, так что проверка «два товара не делят одно фото» проходит.

---

## Древесные материалы — 10 товаров

Фото пока нет, поэтому и таблицы нет — список живёт в `templates.go`.
Когда появятся: завести `photos/wood/`, пронумеровать с `001` и добавить сюда такую же таблицу.
