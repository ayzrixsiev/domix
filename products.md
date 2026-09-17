# Шаблоны товаров

Списки, которыми заполняется каталог магазина сразу после создания.

> **Этот файл больше не является источником.** С миграции 000014 шаблоны живут в таблице
> `product_templates`, и правятся они в админ-панели (`/admin` → Шаблоны): добавить товар, изменить
> название или единицу, удалить. Таблицы ниже — снимок того, что было в базе на момент переноса,
> и остаются здесь как читаемая справка по фотографиям и ключам.

**Как добавить товар:** положить фото в `photos/<категория>/NNN.jpg` под следующим свободным номером →
в админ-панели «Добавить товар», указав путь к фото → «Применить ко всем», если товар нужен и в уже
созданных магазинах.

Фото: `photos/<категория>/NNN.jpg`, путь в поле `image_path` целиком — `universal/001.jpg`.

**Поиск латиницей:** правила в `backend/internal/catalog/translit.go` сами читают «kabel» как «кабел»,
«plitka» как «плитка». Слово добавляется в список `latinAliases` там же только тогда, когда правила
пишут его неправильно — как «sement», которое по правилам вышло бы «семент», а нужно «цемент».

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

## Сантехника — 100 товаров

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 001 | VERO Адаптер-муфта комб. В/Р 25х1/2 | шт | `plumbing.adapter_coupling_female_25` |
| 002 | VERO Адаптер-муфта комб. Н/Р 25х1/2 | шт | `plumbing.adapter_coupling_male_25` |
| 003 | VERO Адаптер с накидной гайкой (ниппель) 25х1/2 | шт | `plumbing.adapter_nipple_25_half` |
| 004 | VERO Двойной отвод с креплением В/Р 20х15 | шт | `plumbing.double_elbow_bracket_female_20` |
| 005 | VERO Двойной отвод с креплением Н/Р 20х15 | шт | `plumbing.double_elbow_bracket_male_20` |
| 006 | VERO Заглушка 25 | шт | `plumbing.plug_25` |
| 007 | VERO Клипса 25 | шт | `plumbing.clip_25` |
| 008 | VERO Крестовина 90° 20 | шт | `plumbing.cross_90_20` |
| 009 | VERO Хомут металлический 45-52 (1 1/2") | шт | `plumbing.clamp_metal_45_52` |
| 010 | VERO Муфта 25 | шт | `plumbing.coupling_25` |
| 011 | VERO Обвод 25 | шт | `plumbing.bypass_25` |
| 012 | VERO Отвод 90° 25 | шт | `plumbing.elbow_90_25` |
| 013 | VERO Отвод с настенным креплением В/Р 20 | шт | `plumbing.elbow_wall_female_20` |
| 014 | VERO Отвод с настенным креплением Н/Р 20 | шт | `plumbing.elbow_wall_male_20` |
| 015 | VERO Переходник 32-20 | шт | `plumbing.reducer_32_20` |
| 016 | VERO Полуотвод 25 | шт | `plumbing.elbow_45_25` |
| 017 | VERO Ракор В/Р 25х3/4 | шт | `plumbing.union_female_25_three_quarter` |
| 018 | VERO Ракор Н/Р 25х1/2 | шт | `plumbing.union_male_25_half` |
| 019 | VERO Тройник 25 | шт | `plumbing.tee_25` |
| 020 | VERO Тройник комб. с В/Р 20х1/2 | шт | `plumbing.tee_female_20_half` |
| 021 | VERO Тройник комб. с Н/Р 25х1/2 | шт | `plumbing.tee_male_25_half` |
| 022 | VERO Тройник переходник 32-20-32 | шт | `plumbing.tee_reducing_32_20_32` |
| 023 | VERO Угловой кран для радиатора 20х1/2 | шт | `plumbing.radiator_valve_angle_20` |
| 024 | VERO Угловой кран для радиатора 20х1/2 (импорт) | шт | `plumbing.radiator_valve_angle_20_import` |
| 025 | VERO Угол В/Р 25х1/2 | шт | `plumbing.elbow_female_25_half` |
| 026 | VERO Угол Н/Р 25х1/2 | шт | `plumbing.elbow_male_25_half` |
| 027 | VERO Угол с накидной гайкой (ниппель) 25х3/4 | шт | `plumbing.elbow_nipple_25_three_quarter` |
| 028 | VERO Фильтр 25 «мама» (латунь) | шт | `plumbing.filter_25_brass` |
| 029 | VERO Шаровой кран 20 | шт | `plumbing.ball_valve_20` |
| 030 | VERO Шаровой кран 20 ECO | шт | `plumbing.ball_valve_20_eco` |
| 031 | Механизм нижний с двухрежимным выпуском | шт | `plumbing.cistern_valve_dual_flush` |
| 032 | Поплавок боковой (пластмасса) | шт | `plumbing.cistern_float_side` |
| 033 | Гофра для унитаза | шт | `plumbing.toilet_corrugation` |
| 034 | Гофра для унитаза угловая | шт | `plumbing.toilet_corrugation_angle` |
| 035 | Крепление для сиденья унитаза | шт | `plumbing.toilet_seat_fixing` |
| 036 | Резина для сифона («вонючка») | шт | `plumbing.siphon_rubber_seal` |
| 037 | Выпуск для сифона (головка) | шт | `plumbing.siphon_outlet_head` |
| 038 | Сифон с тазиком и круглым переливом | шт | `plumbing.siphon_bowl_round_overflow` |
| 039 | Сиденье с крышкой для унитаза | шт | `plumbing.toilet_seat_cover` |
| 040 | Сифон для ванны | шт | `plumbing.siphon_bath` |
| 041 | Сифон для мойки с выпуском и переливом ЭКО | шт | `plumbing.siphon_sink_eco` |
| 042 | Трап сливной для душа, боковой (пластик) | шт | `plumbing.drain_shower_side_plastic` |
| 043 | Трап сливной для душа, прямой (пластик) | шт | `plumbing.drain_shower_straight_plastic` |
| 044 | Трап AQUA 10х10 SS-28 | шт | `plumbing.drain_aqua_ss28` |
| 045 | Трап 12 PRO AQUA 10х10 (никель) | шт | `plumbing.drain_aqua_12pro` |
| 046 | Трап под кафель AQUA 10х10 (никель) | шт | `plumbing.drain_aqua_tile` |
| 047 | Сливной шланг для стиральной машины 190 мм | шт | `plumbing.washer_drain_hose_190` |
| 048 | Сливной шланг для стиральной машины 290 мм | шт | `plumbing.washer_drain_hose_290` |
| 049 | Антивибрационные подставки | шт | `plumbing.anti_vibration_pads` |
| 050 | Шланг наливной 2,5 м | шт | `plumbing.washer_inlet_hose_25` |
| 051 | Механизм для джойстика | шт | `plumbing.mixer_cartridge` |
| 052 | Кран-букса квадрат (латунь), красная | шт | `plumbing.tap_valve_square_brass` |
| 053 | Барашек крестовой NEW | шт | `plumbing.tap_handle_cross_new` |
| 054 | Лапка смесителя | шт | `plumbing.mixer_bracket` |
| 055 | BOOU Фиксатор ZL-115 | шт | `plumbing.boou_fixator_zl115` |
| 056 | Фильтр для гусака с сальником (н/р) | шт | `plumbing.spout_filter_male` |
| 057 | Смеситель-микрофон гусак серый AQUA 19808-27 | шт | `plumbing.mixer_mic_aqua_19808` |
| 058 | Смеситель-микрофон гусак (дешёвый) | шт | `plumbing.mixer_mic_cheap` |
| 059 | Душевой шланг AQUA 1,5-1,8 м AQ-01 | шт | `plumbing.shower_hose_aqua_aq01` |
| 060 | Шланг армированный м/м ALFA 80 см | шт | `plumbing.hose_reinforced_mm_alfa_80` |
| 061 | Шланг армированный м/с ALFA 70 см | шт | `plumbing.hose_reinforced_ms_alfa_70` |
| 062 | Шланг для воды BOOU м/м 100 см | шт | `plumbing.hose_water_boou_100` |
| 063 | Шланг для смесителя BOOU «ёлка» 80 см | шт | `plumbing.hose_mixer_boou_80` |
| 064 | Лейка AQUA AQ-R50 | шт | `plumbing.shower_head_aqua_r50` |
| 065 | Термофлекс 28х6/2 красный | шт | `plumbing.thermoflex_28x6_red` |
| 066 | Термофлекс 28х6/2 синий | шт | `plumbing.thermoflex_28x6_blue` |
| 067 | VERO Канализационная труба 2,2 мм — 100/3 м | шт | `plumbing.sewer_pipe_100_3m` |
| 068 | VERO Канализационная труба 2,2 мм — 50/3 м | шт | `plumbing.sewer_pipe_50_3m` |
| 069 | VERO Канализационная труба 2,2 мм — 75/3 м | шт | `plumbing.sewer_pipe_75_3m` |
| 070 | VERO Канализационная труба 3,2 мм — 150/3 м | шт | `plumbing.sewer_pipe_150_3m` |
| 071 | VERO (к) Клипса 100 | шт | `plumbing.sewer_clip_100` |
| 072 | VERO (к) Клипса 50 | шт | `plumbing.sewer_clip_50` |
| 073 | VERO (к) Муфта 110 | шт | `plumbing.sewer_coupling_110` |
| 074 | VERO (к) Отвод 100 | шт | `plumbing.sewer_elbow_100` |
| 075 | VERO (к) Полуотвод 100 | шт | `plumbing.sewer_elbow_45_100` |
| 076 | VERO (к) Тройник 100/100 90° | шт | `plumbing.sewer_tee_100_100` |
| 077 | VERO (к) Тройник 100/50 90° | шт | `plumbing.sewer_tee_100_50` |
| 078 | Бочонок (дешёвый) 15 | шт | `plumbing.barrel_nipple_15_cheap` |
| 079 | Бочонок латунный (сальник) 15 | шт | `plumbing.barrel_nipple_15_brass` |
| 080 | Заглушка 20 М (дешёвая) | шт | `plumbing.plug_20_male_cheap` |
| 081 | Кальсо (дешёвое) 15х20 М-П | шт | `plumbing.calso_15x20_cheap` |
| 082 | Кальсо нержавейка 15х20 М-П | шт | `plumbing.calso_15x20_steel` |
| 083 | Муфта нержавейка 20 (304) | шт | `plumbing.coupling_20_steel` |
| 084 | Отвод 15 М-М (латунный) | шт | `plumbing.elbow_15_brass` |
| 085 | Отвод нержавейка 15 (304) М-П | шт | `plumbing.elbow_15_steel` |
| 086 | Переходник нержавейка 20х25 П-П | шт | `plumbing.reducer_20x25_steel` |
| 087 | Тройник 15 М-М-М (латунный) | шт | `plumbing.tee_15_mmm_brass` |
| 088 | Тройник 15 М-М-П (латунный) | шт | `plumbing.tee_15_mmf_brass` |
| 089 | Штуцер 15 н/р (дешёвый) | шт | `plumbing.nipple_15_male_cheap` |
| 090 | Эксцентрик (латунный) 90 | шт | `plumbing.eccentric_brass_90` |
| 091 | Удлинитель 1,5 см | шт | `plumbing.extension_15` |
| 092 | Муфта 16 | шт | `plumbing.coupling_16` |
| 093 | Отвод (латунный) 16 КТМ | шт | `plumbing.elbow_16_ktm` |
| 094 | Тройник 16 КТМ | шт | `plumbing.tee_16_ktm` |
| 095 | BOOU Смеситель для душа B8156-5S (Ж) | шт | `plumbing.boou_mixer_shower_b8156_5s` |
| 096 | BOOU Смеситель стояк 7195-75 (Ж) | шт | `plumbing.boou_mixer_riser_7195` |
| 097 | BOOU Смеситель-микрофон BZ9184J-E367 (Ж) | шт | `plumbing.boou_mixer_mic_bz9184j` |
| 098 | BOOU Смеситель B8156-14A (Ж) | шт | `plumbing.boou_mixer_b8156_14a` |
| 099 | Электрический смеситель ALFA | шт | `plumbing.mixer_electric_alfa` |
| 100 | BOOU Смеситель «тахорат» B8246-4AH-F805 (Ж) | шт | `plumbing.boou_mixer_bidet_b8246` |

---

## Пиломатериалы — 5 товаров

| № | Товар | Ед. | Ключ |
| --- | --- | --- | --- |
| 001 | Брус 50х100х6000 | шт | `wood.beam_50x100` |
| 002 | Доска 25х150х6000 | шт | `wood.board_25x150` |
| 003 | Таб-рейка 30х40 | м | `wood.batten_30x40` |
| 004 | Фанера 18 мм, 1525х1525 | лист | `wood.plywood_18` |
| 005 | Стропила 50х150х6000 | шт | `wood.rafter_50x150` |

Все — категория `lumber`, фото `photos/wood/NNN.jpg`. Прежние десять позиций (вагонка, ОСБ, ДСП,
МДФ, половая доска) удалены миграцией 000005 вместе со своими ключами; выжил только
`wood.board_25x150` — 25х150х6000 в новом наборе тот же товар, что и в старом.

**Пять, а не десять.** В сравнение цен попадает только магазин, проставивший цену на каждую строку
шаблона — одной пустой хватает, чтобы он выпал целиком. Список из десяти позиций, половину которых
магазин не возит, это шаблон, по которому не ранжируется никто.

**Единицы.** У рейки цена за метр: длины в названии нет, а магазин с трёхметровой рейкой не должен
выглядеть вдвое дешевле магазина с шестиметровой. У фанеры формат листа вписан в название — тогда
«лист» сравним, и владельцу не приходится делить свою цену на площадь.

**Фотографии закрывают строку.** Право поставить свой снимок даётся только там, где у каталога
снимка нет, и вычисляется из самого шаблона (`templateFlags` в `internal/endpoints/product_crud.go`).
До 000005 древесные строки были на разрешающей стороне правила; съёмка перевела их на запрещающую
сама, без единой правки в коде.
