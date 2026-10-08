-- one size is one card again: the size groups go, and a row carries its own description line
-- («Квадратная · 24 Вт · 6500 К») plus the section a shop's grid files it under.

ALTER TABLE product_templates
    DROP CONSTRAINT product_templates_variant_pair,
    DROP COLUMN variant_group,
    DROP COLUMN variant_label,
    ADD COLUMN specs VARCHAR(80) NOT NULL DEFAULT '',
    ADD COLUMN section VARCHAR(40) NOT NULL DEFAULT '';

ALTER TABLE products
    DROP CONSTRAINT products_variant_pair,
    DROP COLUMN variant_group,
    DROP COLUMN variant_label,
    ADD COLUMN specs VARCHAR(80) NOT NULL DEFAULT '',
    ADD COLUMN section VARCHAR(40) NOT NULL DEFAULT '';

-- **search reads the name and the description as one string**: the sizes moved out of the names,
-- and «диск 125» has to keep finding the 125 mm disc. the query must repeat this expression exactly.
DROP INDEX idx_products_search_name;
CREATE INDEX idx_products_search_text ON products
    USING gin (translate(lower(name || ' ' || specs), 'ё', 'е') gin_trgm_ops)
    WHERE price IS NOT NULL;

-- the universal catalogue, renamed. keys stay as they were: they are what prices are compared by.
UPDATE product_templates t
SET name = v.name, specs = v.specs, section = v.section, updated_at = CURRENT_TIMESTAMP
FROM (VALUES
    ('universal.tape_45x50', 'Скотч упаковочный', '45 мм × 50 м · Прозрачный', 'tapes_abrasives'),
    ('universal.tape_45x40', 'Малярная лента', '45 мм × 40 м · Бумажная · Жёлтая', 'tapes_abrasives'),
    ('universal.tape_double_sided_20', 'Скотч двухсторонний', '20 мм × 3 м · Прозрачный', 'tapes_abrasives'),
    ('universal.insulating_tape', 'Изолента', 'ПВХ · Чёрная · Vini Tape', 'tapes_abrasives'),
    ('universal.gloves', 'Перчатки рабочие', 'Зелёные', 'tapes_abrasives'),
    ('universal.sandpaper_cloth', 'Наждачная бумага', 'Рулон · Тканевая основа · Россия', 'tapes_abrasives'),
    ('universal.sandpaper_holder', 'Держатель для наждачной бумаги', '190 × 90 мм · Ручной', 'tapes_abrasives'),
    ('universal.grinding_disc_50', 'Шлифовальный диск', '100 мм · P50 · EN-PD', 'tapes_abrasives'),
    ('universal.grinding_disc_1000', 'Шлифовальный диск', '100 мм · P1000 · EN-PD', 'tapes_abrasives'),
    ('universal.grinding_disc_1500', 'Шлифовальный диск', '100 мм · P1500 · EN-PD', 'tapes_abrasives'),
    ('universal.diamond_disc_adp_125', 'Алмазный диск', '125 мм · 1ADP · EPA', 'tapes_abrasives'),
    ('universal.diamond_disc_ads_125', 'Алмазный диск', '125 мм · 1ADS · EPA', 'tapes_abrasives'),
    ('universal.diamond_disc_adm_125', 'Алмазный диск', '125 мм · 1ADM · EPA', 'tapes_abrasives'),
    ('universal.cutting_disc_luga_180', 'Отрезной диск', '180 мм · Оригинал · LUGA', 'tapes_abrasives'),
    ('universal.cutting_disc_epa_125', 'Отрезной диск', '125 мм · Оригинал · EPA', 'tapes_abrasives'),
    ('universal.saw_disc_epa_180', 'Пильный диск', '180 мм · 1PD · EPA', 'tapes_abrasives'),
    ('universal.core_bit_25', 'Алмазная коронка', '25 мм · Алмазное напыление', 'tapes_abrasives'),
    ('universal.core_bit_75', 'Алмазная коронка', '75 мм · Алмазное напыление', 'tapes_abrasives'),
    ('universal.metal_drill_6', 'Сверло по металлу', '6 мм · Спиральное · Цилиндрический хвостовик', 'drills_hand_tools'),
    ('universal.sds_drill_6x120', 'Бур по бетону', '6 × 120 мм · SDS Plus · LIT', 'drills_hand_tools'),
    ('universal.sds_drill_10x350', 'Бур по бетону', '10 × 350 мм · SDS Plus · LIT', 'drills_hand_tools'),
    ('universal.screwdriver_bit_ph2', 'Бита для шуруповёрта', 'PH2 · 65 мм · Двусторонняя', 'drills_hand_tools'),
    ('universal.screwdriver_06x4', 'Отвёртка шлицевая', '0,6 × 4 мм · Плоский шлиц', 'drills_hand_tools'),
    ('universal.spatula_250', 'Шпатель малярный', '250 мм', 'drills_hand_tools'),
    ('universal.spatula_400', 'Шпатель малярный', '400 мм', 'drills_hand_tools'),
    ('universal.wrench_10', 'Ключ комбинированный', '10 мм · Рожково-накидной', 'drills_hand_tools'),
    ('universal.wrench_19', 'Ключ комбинированный', '19 мм · Рожково-накидной', 'drills_hand_tools'),
    ('universal.hammer_rubber', 'Киянка резиновая', 'Резиновый боёк · Деревянная рукоятка', 'drills_hand_tools'),
    ('universal.hammer_steel_1kg', 'Молоток слесарный', '1 кг · LIT', 'drills_hand_tools'),
    ('universal.utility_knife_18', 'Нож канцелярский', '18 мм · Сегментное лезвие', 'drills_hand_tools'),
    ('universal.utility_blades_18', 'Лезвия для канцелярского ножа', '18 мм · Сегментные · 10 шт', 'drills_hand_tools'),
    ('universal.tape_measure_5m', 'Рулетка', '5 м · Auto Stop · LIT', 'drills_hand_tools'),
    ('universal.tape_measure_10m', 'Рулетка', '10 м · Auto Stop · LIT', 'drills_hand_tools'),
    ('universal.foam_gun', 'Пистолет для монтажной пены', 'Металлический корпус', 'drills_hand_tools'),
    ('universal.sealant_gun', 'Пистолет для герметика', 'Скелетный · Для картриджей', 'drills_hand_tools'),
    ('universal.builders_line', 'Леска строительная', 'Красная · В мотке', 'drills_hand_tools'),
    ('universal.welding_mask', 'Маска сварочная «Хамелеон»', 'Автозатемнение · Чёрная', 'drills_hand_tools'),
    ('universal.welding_electrodes_3', 'Электроды сварочные', '3 мм · Арсенал', 'drills_hand_tools'),
    ('universal.switch_2g_flush', 'Выключатель двухклавишный', 'Встраиваемый · Белый', 'electrical_lighting'),
    ('universal.switch_2g_surface', 'Выключатель двухклавишный', 'Накладной · Белый', 'electrical_lighting'),
    ('universal.socket_2g_flush', 'Розетка двойная', 'Встраиваемая · Белая', 'electrical_lighting'),
    ('universal.socket_2g_surface', 'Розетка двойная', 'Накладная · Белая', 'electrical_lighting'),
    ('universal.socket_box_ring', 'Подрозетник монтажный', 'Круглый · Красный', 'electrical_lighting'),
    ('universal.led_lamp_10w', 'LED-лампа', '10 Вт · E27', 'electrical_lighting'),
    ('universal.led_lamp_60w', 'LED-лампа', '60 Вт · E27', 'electrical_lighting'),
    ('universal.lamp_holder', 'Патрон для лампы', 'E27 · Пластик · Чёрный', 'electrical_lighting'),
    ('universal.led_panel_recessed_square_24w', 'LED-панель встраиваемая', 'Квадратная · 24 Вт · 6500 К', 'electrical_lighting'),
    ('universal.led_panel_recessed_round_24w', 'LED-панель встраиваемая', 'Круглая · 24 Вт · 6500 К', 'electrical_lighting'),
    ('universal.led_panel_surface_square_24w', 'LED-панель накладная', 'Квадратная · 24 Вт · 6500 К', 'electrical_lighting'),
    ('universal.led_panel_surface_round_24w', 'LED-панель накладная', 'Круглая · 24 Вт · 6500 К', 'electrical_lighting'),
    ('universal.extension_block_3', 'Колодка для удлинителя', '3 розетки · Без кабеля · Зелёная', 'electrical_lighting'),
    ('universal.plug_16a', 'Вилка электрическая', 'Турецкая · 16 А · 250 В', 'electrical_lighting'),
    ('universal.cable_pvs_2x15_white', 'Кабель ПВС', '2 × 1,5 мм² · Медный · Белый', 'electrical_lighting'),
    ('universal.cable_pvs_2x15_black', 'Кабель ПВС', '2 × 1,5 мм² · Медный · Чёрный', 'electrical_lighting'),
    ('universal.cable_pvs_2x25_black', 'Кабель ПВС', '2 × 2,5 мм² · Медный · Чёрный', 'electrical_lighting'),
    ('universal.screws', 'Саморез', 'Чёрный · Потайная головка', 'fasteners_mounting'),
    ('universal.screws_drill_16', 'Саморезы с прессшайбой', '16 мм · С широкой шляпкой', 'fasteners_mounting'),
    ('universal.screws_roofing', 'Саморезы кровельные', 'Шестигранная головка · EPDM-шайба', 'fasteners_mounting'),
    ('universal.nails', 'Гвозди', 'Стальные', 'fasteners_mounting'),
    ('universal.bolts_galvanized', 'Болт оцинкованный', 'Шестигранная головка', 'fasteners_mounting'),
    ('universal.nuts_galvanized', 'Гайка оцинкованная', 'Шестигранная', 'fasteners_mounting'),
    ('universal.washers_galvanized', 'Шайба оцинкованная', 'Плоская', 'fasteners_mounting'),
    ('universal.anchor_bolt_10x120', 'Анкер-болт', '10 × 120 мм · С гайкой', 'fasteners_mounting'),
    ('universal.anchor_frame_10x112', 'Анкер рамный', '10 × 112 мм · Под отвёртку', 'fasteners_mounting'),
    ('universal.dowel_6x60', 'Дюбель', '6 × 60 мм · Пластиковый', 'fasteners_mounting'),
    ('universal.dowel_screw_6x60', 'Дюбель с саморезом', '6 × 60 мм', 'fasteners_mounting'),
    ('universal.dowel_umbrella_10x120', 'Дюбель-зонт', '10 × 120 мм · Для теплоизоляции', 'fasteners_mounting'),
    ('universal.dowel_nail', 'Дюбель-гвоздь', 'С металлическим гвоздём', 'fasteners_mounting'),
    ('universal.powder_nails_27', 'Дюбель-гвоздь для порохового пистолета', '27 мм · С шайбой', 'fasteners_mounting'),
    ('universal.cable_tie_white_250', 'Хомут нейлоновый', '250 мм · 100 шт · Белый', 'fasteners_mounting'),
    ('universal.cable_tie_black_250', 'Хомут нейлоновый', '250 мм · 100 шт · Чёрный', 'fasteners_mounting'),
    ('universal.padlock_70', 'Замок навесной', '70 мм · С ключами', 'fasteners_mounting'),
    ('universal.tile_leveling_clip_14', 'Зажим СВП', '1,4 мм · 250 шт', 'fasteners_mounting'),
    ('universal.tile_leveling_wedge_14', 'Клин СВП', 'Для СВП 1,4 мм · 100 шт', 'fasteners_mounting'),
    ('universal.rotband_25', 'Штукатурка гипсовая', '25 кг · Rotband · Knauf', 'mixes_paints'),
    ('universal.fugen_25', 'Шпаклёвка гипсовая', '25 кг · Fugen · Knauf', 'mixes_paints'),
    ('universal.putty_eleron_05', 'Штукатурка гипсовая', '20 кг · Для внутренних работ · Элерон C-05', 'mixes_paints'),
    ('universal.putty_eleron_01', 'Шпатлёвка гипсовая', '20 кг · Для внутренних работ · Элерон C-01', 'mixes_paints'),
    ('universal.putty_eleron_001', 'Шпатлёвка суперфинишная', '20 кг · Для внутренних работ · Элерон C-001', 'mixes_paints'),
    ('universal.tile_glue_megamix_22', 'Клей плиточный усиленный', '25 кг · L22 · Megamix', 'mixes_paints'),
    ('universal.foam_tytan_65', 'Пена монтажная', 'Универсальная · UNI 65 · TYTAN', 'mixes_paints'),
    ('universal.silicone_akfix_100e', 'Силикон универсальный', 'Прозрачный · 100E · Akfix', 'mixes_paints'),
    ('universal.glue_tytan_classic_fix', 'Клей монтажный', '310 мл · Classic Fix · TYTAN', 'mixes_paints'),
    ('universal.glue_akfix_705', 'Клей двухкомпонентный', '705 · Большой комплект · Akfix', 'mixes_paints'),
    ('universal.pva_eron', 'Клей ПВА', 'Оригинальный · Иран · Эрон', 'mixes_paints'),
    ('universal.enamel_hayat_pf115', 'Краска алкидная', 'ПФ-115 · 3 кг · Белая · Hayat', 'mixes_paints'),
    ('universal.tint_palizh', 'Колер универсальный', 'Palizh', 'mixes_paints'),
    ('universal.tint_pufamix', 'Колер-концентрат', 'Original · PUFAMIX', 'mixes_paints'),
    ('universal.solvent_646', 'Растворитель', 'В-646 · 1 л · Вершина', 'mixes_paints'),
    ('universal.thinner', 'Разбавитель акриловый', '1 л', 'mixes_paints'),
    ('universal.brush_3', 'Кисть для водоэмульсионных красок', 'Плоская · Пластиковая рукоятка', 'mixes_paints'),
    ('universal.brush_4', 'Кисть для водоэмульсионных красок', 'Плоская · Деревянная рукоятка', 'mixes_paints'),
    ('universal.masking_film_180', 'Плёнка защитная', '180 см · С малярной лентой', 'films_sheets'),
    ('universal.film_white_06', 'Плёнка полиэтиленовая', '0,6 мм · Белая', 'films_sheets'),
    ('universal.film_black_06', 'Плёнка полиэтиленовая', '0,6 мм · Чёрная', 'films_sheets'),
    ('universal.roll_insulation_03', 'Изоляция рулонная', '0,3 мм · Синтепон · Заводская', 'films_sheets'),
    ('universal.roll_insulation_05', 'Изоляция рулонная', '0,5 мм · Синтепон · Заводская', 'films_sheets'),
    ('universal.drywall_wall', 'Гипсокартон', 'Стеновой · Обычный', 'films_sheets'),
    ('universal.drywall_moisture', 'Гипсокартон', 'Стеновой · Влагостойкий', 'films_sheets'),
    ('universal.drywall_ceiling', 'Гипсокартон', 'Потолочный · Обычный', 'films_sheets')
) AS v(template_key, name, specs, section)
WHERE t.template_key = v.template_key;

-- and into every universal shop already seeded, the way the sync button would
UPDATE products p
SET name = t.name, specs = t.specs, section = t.section, updated_at = CURRENT_TIMESTAMP
FROM product_templates t
WHERE p.template_key = t.template_key
  AND t.shop_category = 'universal';
