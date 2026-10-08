-- back to size groups and the old names. photos are not touched in either direction.

DROP INDEX idx_products_search_text;
CREATE INDEX idx_products_search_name ON products
    USING gin (translate(lower(name), 'ё', 'е') gin_trgm_ops)
    WHERE price IS NOT NULL;

ALTER TABLE product_templates
    DROP COLUMN specs,
    DROP COLUMN section,
    ADD COLUMN variant_group VARCHAR(80),
    ADD COLUMN variant_label VARCHAR(40),
    ADD CONSTRAINT product_templates_variant_pair
        CHECK ((variant_group IS NULL) = (variant_label IS NULL));

ALTER TABLE products
    DROP COLUMN specs,
    DROP COLUMN section,
    ADD COLUMN variant_group VARCHAR(80),
    ADD COLUMN variant_label VARCHAR(40),
    ADD CONSTRAINT products_variant_pair
        CHECK ((variant_group IS NULL) = (variant_label IS NULL));

UPDATE product_templates t
SET name = v.name, variant_group = v.variant_group, variant_label = v.variant_label,
    updated_at = CURRENT_TIMESTAMP
FROM (VALUES
    ('universal.tape_45x50', 'Скотч упаковочный 4,5х50', 'Скотч упаковочный', '4,5х50'),
    ('universal.tape_45x40', 'Скотч упаковочный 4,5х40', 'Скотч упаковочный', '4,5х40'),
    ('universal.tape_double_sided_20', 'Скотч двухсторонний прозрачный 20 мм х 3 м', NULL, NULL),
    ('universal.gloves', 'Перчатки рабочие (зелёные)', NULL, NULL),
    ('universal.sandpaper_cloth', 'Наждачная бумага на тканевой основе (Россия)', NULL, NULL),
    ('universal.sandpaper_holder', 'Держатель для наждачной бумаги 190х90', NULL, NULL),
    ('universal.grinding_disc_50', 'Диск шлифовальный EN-PD-100-50', 'Диск шлифовальный EN-PD-100', '50'),
    ('universal.grinding_disc_1000', 'Диск шлифовальный EN-PD-100-1000', 'Диск шлифовальный EN-PD-100', '1000'),
    ('universal.grinding_disc_1500', 'Диск шлифовальный EN-PD-100-1500', 'Диск шлифовальный EN-PD-100', '1500'),
    ('universal.diamond_disc_adp_125', 'Диск алмазный 1ADP-EPA-125', NULL, NULL),
    ('universal.diamond_disc_ads_125', 'Диск алмазный 1ADS-EPA-125', NULL, NULL),
    ('universal.diamond_disc_adm_125', 'Диск алмазный 1ADM-EPA-125', NULL, NULL),
    ('universal.cutting_disc_luga_180', 'Диск отрезной LUGA 180', NULL, NULL),
    ('universal.cutting_disc_epa_125', 'Диск отрезной EPA-125', NULL, NULL),
    ('universal.saw_disc_epa_180', 'Диск пильный EPA 1PD-180', NULL, NULL),
    ('universal.core_bit_25', 'Коронка алмазная 25 мм', 'Коронка алмазная', '25 мм'),
    ('universal.core_bit_75', 'Коронка алмазная 75 мм', 'Коронка алмазная', '75 мм'),
    ('universal.metal_drill_6', 'Сверло по металлу 6 мм', NULL, NULL),
    ('universal.sds_drill_6x120', 'Бур по бетону SDS plus 6х120 Lit', 'Бур по бетону SDS plus Lit', '6х120'),
    ('universal.sds_drill_10x350', 'Бур по бетону SDS plus 10х350 Lit', 'Бур по бетону SDS plus Lit', '10х350'),
    ('universal.screwdriver_bit_ph2', 'Насадка для шуруповёрта PH2х65', NULL, NULL),
    ('universal.screwdriver_06x4', 'Отвёртка 0,6х4', NULL, NULL),
    ('universal.spatula_250', 'Шпатель 250 мм', 'Шпатель', '250 мм'),
    ('universal.spatula_400', 'Шпатель 400 мм', 'Шпатель', '400 мм'),
    ('universal.wrench_10', 'Ключ комбинированный 10 мм', 'Ключ комбинированный', '10 мм'),
    ('universal.wrench_19', 'Ключ комбинированный 19 мм', 'Ключ комбинированный', '19 мм'),
    ('universal.hammer_rubber', 'Молоток резиновый', NULL, NULL),
    ('universal.hammer_steel_1kg', 'Молоток железный 1 кг Lit', NULL, NULL),
    ('universal.utility_knife_18', 'Нож канцелярский 18 мм', NULL, NULL),
    ('universal.utility_blades_18', 'Лезвия для канцелярского ножа 18 мм, 10 шт', NULL, NULL),
    ('universal.tape_measure_5m', 'Рулетка 5 м Lit', 'Рулетка Lit', '5 м'),
    ('universal.tape_measure_10m', 'Рулетка 10 м Lit', 'Рулетка Lit', '10 м'),
    ('universal.foam_gun', 'Пистолет для монтажной пены', NULL, NULL),
    ('universal.sealant_gun', 'Пистолет для герметика', NULL, NULL),
    ('universal.builders_line', 'Леска строительная', NULL, NULL),
    ('universal.welding_mask', 'Маска сварочная «хамелеон»', NULL, NULL),
    ('universal.welding_electrodes_3', 'Электроды Арсенал 3 мм', NULL, NULL),
    ('universal.switch_2g_flush', 'Выключатель внутренний 2-клавишный (белый)', NULL, NULL),
    ('universal.switch_2g_surface', 'Выключатель наружный 2-клавишный (белый)', NULL, NULL),
    ('universal.socket_2g_flush', 'Розетка внутренняя 2-местная (белая)', NULL, NULL),
    ('universal.socket_2g_surface', 'Розетка наружная 2-местная (белая)', NULL, NULL),
    ('universal.socket_box_ring', 'Кольцо-подрозетник', NULL, NULL),
    ('universal.led_lamp_10w', 'Лампочка светодиодная 10 Вт', 'Лампочка светодиодная', '10 Вт'),
    ('universal.led_lamp_60w', 'Лампочка светодиодная 60 Вт', 'Лампочка светодиодная', '60 Вт'),
    ('universal.lamp_holder', 'Патрон для ламп', NULL, NULL),
    ('universal.led_panel_recessed_square_24w', 'LED-панель встраиваемая, квадратная 24 Вт 6500K', NULL, NULL),
    ('universal.led_panel_recessed_round_24w', 'LED-панель встраиваемая, круглая 24 Вт 6500K', NULL, NULL),
    ('universal.led_panel_surface_square_24w', 'LED-панель накладная, квадратная 24 Вт 6500K', NULL, NULL),
    ('universal.led_panel_surface_round_24w', 'LED-панель накладная, круглая 24 Вт 6500K', NULL, NULL),
    ('universal.extension_block_3', 'Колодка удлинителя, 3 розетки, без кабеля', NULL, NULL),
    ('universal.plug_16a', 'Вилка электрическая турецкая, 16А 250В', NULL, NULL),
    ('universal.cable_pvs_2x15_white', 'Кабель медный ПВС 2х1,5, белый', NULL, NULL),
    ('universal.cable_pvs_2x15_black', 'Кабель медный ПВС 2х1,5, чёрный', 'Кабель медный ПВС, чёрный', '2х1,5'),
    ('universal.cable_pvs_2x25_black', 'Кабель медный ПВС 2х2,5, чёрный', 'Кабель медный ПВС, чёрный', '2х2,5'),
    ('universal.insulating_tape', 'Изолента Vini Tape', NULL, NULL),
    ('universal.screws', 'Саморезы', NULL, NULL),
    ('universal.screws_drill_16', 'Саморезы «семечки» 1,6 мм', NULL, NULL),
    ('universal.screws_roofing', 'Саморезы кровельные', NULL, NULL),
    ('universal.nails', 'Гвозди', NULL, NULL),
    ('universal.bolts_galvanized', 'Болты оцинкованные', NULL, NULL),
    ('universal.nuts_galvanized', 'Гайка оцинкованная', NULL, NULL),
    ('universal.washers_galvanized', 'Шайба оцинкованная', NULL, NULL),
    ('universal.anchor_bolt_10x120', 'Анкер-болт с гайкой 10х120', NULL, NULL),
    ('universal.anchor_frame_10x112', 'Анкер рамный (под отвёртку) 10х112', NULL, NULL),
    ('universal.dowel_6x60', 'Дюбель 6х60', NULL, NULL),
    ('universal.dowel_umbrella_10x120', 'Дюбель-зонт 10х120 мм', NULL, NULL),
    ('universal.dowel_screw_6x60', 'Дюбель-саморез 6х60', NULL, NULL),
    ('universal.dowel_nail', 'Дюбель-гвоздь', NULL, NULL),
    ('universal.powder_nails_27', 'Дюбель-гвозди для порохового пистолета 27 мм, 200 шт', NULL, NULL),
    ('universal.cable_tie_white_250', 'Хомут нейлоновый белый 250 мм, 100 шт', NULL, NULL),
    ('universal.cable_tie_black_250', 'Хомут нейлоновый чёрный 250 мм, 100 шт', NULL, NULL),
    ('universal.padlock_70', 'Замок навесной 70 мм', NULL, NULL),
    ('universal.rotband_25', 'Кнауф Ротбанд, 25 кг', NULL, NULL),
    ('universal.fugen_25', 'Кнауф Фуген, 25 кг', NULL, NULL),
    ('universal.tile_glue_megamix_22', 'Клей плиточный усиленный Megamix 22', NULL, NULL),
    ('universal.putty_eleron_01', 'Шпатлёвка Элерон 01 для внутренних работ, 20 кг', NULL, NULL),
    ('universal.putty_eleron_05', 'Шпатлёвка гипсовая Элерон 05, 20 кг', NULL, NULL),
    ('universal.putty_eleron_001', 'Шпатлёвка суперфинишная Элерон 001', NULL, NULL),
    ('universal.foam_tytan_65', 'Пена монтажная универсальная TYTAN 65', NULL, NULL),
    ('universal.silicone_akfix_100e', 'Силикон универсальный прозрачный Akfix 100E', NULL, NULL),
    ('universal.glue_tytan_classic_fix', 'Клей монтажный TYTAN Classic Fix, 310 мл', NULL, NULL),
    ('universal.glue_akfix_705', 'Клей двухкомпонентный Akfix 705 (большой)', NULL, NULL),
    ('universal.pva_eron', 'Клей ПВА Эрон', NULL, NULL),
    ('universal.enamel_hayat_pf115', 'Краска Hayat PF-115 Emali', NULL, NULL),
    ('universal.tint_palizh', 'Колер Palizh', NULL, NULL),
    ('universal.tint_pufamix', 'Колер PUFAMIX, оригинал', NULL, NULL),
    ('universal.solvent_646', 'Растворитель Б-646', NULL, NULL),
    ('universal.thinner', 'Разбавитель', NULL, NULL),
    ('universal.brush_3', 'Кисть для водоэмульсионных красок 3"', 'Кисть для водоэмульсионных красок', '3"'),
    ('universal.brush_4', 'Кисть для водоэмульсионных красок 4"', 'Кисть для водоэмульсионных красок', '4"'),
    ('universal.masking_film_180', 'Плёнка защитная с малярным скотчем, 180 см', NULL, NULL),
    ('universal.drywall_wall', 'Гипсокартон стеновой', NULL, NULL),
    ('universal.drywall_ceiling', 'Гипсокартон потолочный', NULL, NULL),
    ('universal.drywall_moisture', 'Гипсокартон стеновой влагостойкий', NULL, NULL),
    ('universal.tile_leveling_clip_14', 'СВП зажим 1,4 мм, 250 шт', NULL, NULL),
    ('universal.tile_leveling_wedge_14', 'СВП клин 1,4 мм, 100 шт', NULL, NULL),
    ('universal.roll_insulation_03', 'Изоляция рулонная (синтепон), завод 03', 'Изоляция рулонная (синтепон), завод', '03'),
    ('universal.roll_insulation_05', 'Изоляция рулонная (синтепон), завод 05', 'Изоляция рулонная (синтепон), завод', '05'),
    ('universal.film_black_06', 'Плёнка полиэтиленовая 0,6, чёрная', NULL, NULL),
    ('universal.film_white_06', 'Плёнка полиэтиленовая 0,6, белая', NULL, NULL)
) AS v(template_key, name, variant_group, variant_label)
WHERE t.template_key = v.template_key;

UPDATE product_templates t
SET variant_group = v.variant_group, variant_label = v.variant_label
FROM (VALUES
    ('plumbing.washer_drain_hose_190', 'Сливной шланг для стиральной машины', '190 мм'),
    ('plumbing.washer_drain_hose_290', 'Сливной шланг для стиральной машины', '290 мм'),
    ('plumbing.sewer_pipe_100_3m', 'VERO Канализационная труба 3 м', 'Ø100'),
    ('plumbing.sewer_pipe_50_3m', 'VERO Канализационная труба 3 м', 'Ø50'),
    ('plumbing.sewer_pipe_75_3m', 'VERO Канализационная труба 3 м', 'Ø75'),
    ('plumbing.sewer_pipe_150_3m', 'VERO Канализационная труба 3 м', 'Ø150'),
    ('plumbing.sewer_clip_100', 'VERO (к) Клипса', 'Ø100'),
    ('plumbing.sewer_clip_50', 'VERO (к) Клипса', 'Ø50'),
    ('plumbing.sewer_tee_100_100', 'VERO (к) Тройник 90°', '100/100'),
    ('plumbing.sewer_tee_100_50', 'VERO (к) Тройник 90°', '100/50')
) AS v(template_key, variant_group, variant_label)
WHERE t.template_key = v.template_key;

UPDATE products p
SET name = CASE WHEN t.shop_category = 'universal' THEN t.name ELSE p.name END,
    variant_group = t.variant_group,
    variant_label = t.variant_label,
    updated_at = CURRENT_TIMESTAMP
FROM product_templates t
WHERE p.template_key = t.template_key
  AND (t.shop_category = 'universal' OR t.variant_group IS NOT NULL);
