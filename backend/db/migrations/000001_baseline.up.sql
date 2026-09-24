CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100),
    phone VARCHAR(50) UNIQUE NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'customer'
        CHECK (role IN ('customer', 'shop_owner', 'admin')),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE shops (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    address TEXT NOT NULL,
    contact_phone VARCHAR(50) NOT NULL DEFAULT '',
    image_url VARCHAR(255),
    category VARCHAR(30) NOT NULL DEFAULT 'universal'
        CHECK (category IN ('universal', 'plumbing', 'wood', 'wallpaper')),
    rating NUMERIC(2, 1) NOT NULL DEFAULT 0.0,
    vip_until TIMESTAMP WITH TIME ZONE,
    location GEOMETRY(Point, 4326),

    -- an admin lever, separate from catalogue completeness: shop_basket_index already answers "is
    -- every template product priced" and is derived from products, where this is for a shop
    -- suspended for a reason prices know nothing about - a rules violation, a dispute.
    excluded_from_index BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_shops_location ON shops USING GIST (location);
CREATE INDEX idx_shops_user_id ON shops (user_id);
CREATE INDEX idx_shops_vip_until ON shops (vip_until) WHERE vip_until IS NOT NULL;

CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    shop_id BIGINT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    template_key VARCHAR(60),
    name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL DEFAULT '',
    price BIGINT,
    availability VARCHAR(20) NOT NULL DEFAULT 'in_stock'
        CHECK (availability IN ('in_stock', 'on_order', 'unavailable')),
    image_path VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_products_shop_template ON products (shop_id, template_key);
CREATE INDEX idx_products_category_priced ON products (category, shop_id) WHERE price IS NOT NULL;

CREATE TABLE product_templates (
    id BIGSERIAL PRIMARY KEY,
    shop_category VARCHAR(50) NOT NULL,
    template_key VARCHAR(60) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    image_path TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_product_templates_category ON product_templates (shop_category, id);

-- the catalogue for each of the four shop categories. **order matters**: a shop's catalogue sorts by
-- template id, so this is the order an owner prices things in, and it matches photos/<category>/.

INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path) VALUES
  ('universal', 'universal.tape_45x50', 'Скотч упаковочный 4,5х50', 'tools', 'шт', 'universal/001.jpg'),
  ('universal', 'universal.tape_45x40', 'Скотч упаковочный 4,5х40', 'tools', 'шт', 'universal/002.jpg'),
  ('universal', 'universal.tape_double_sided_20', 'Скотч двухсторонний прозрачный 20 мм х 3 м', 'tools', 'шт', 'universal/057.jpg'),
  ('universal', 'universal.gloves', 'Перчатки рабочие (зелёные)', 'tools', 'пара', 'universal/007.jpg'),
  ('universal', 'universal.sandpaper_cloth', 'Наждачная бумага на тканевой основе (Россия)', 'tools', 'м', 'universal/006.jpg'),
  ('universal', 'universal.sandpaper_holder', 'Держатель для наждачной бумаги 190х90', 'tools', 'шт', 'universal/036.jpg'),
  ('universal', 'universal.grinding_disc_50', 'Диск шлифовальный EN-PD-100-50', 'tools', 'шт', 'universal/020.jpg'),
  ('universal', 'universal.grinding_disc_1000', 'Диск шлифовальный EN-PD-100-1000', 'tools', 'шт', 'universal/021.jpg'),
  ('universal', 'universal.grinding_disc_1500', 'Диск шлифовальный EN-PD-100-1500', 'tools', 'шт', 'universal/022.jpg'),
  ('universal', 'universal.diamond_disc_adp_125', 'Диск алмазный 1ADP-EPA-125', 'tools', 'шт', 'universal/016.jpg'),
  ('universal', 'universal.diamond_disc_ads_125', 'Диск алмазный 1ADS-EPA-125', 'tools', 'шт', 'universal/018.jpg'),
  ('universal', 'universal.diamond_disc_adm_125', 'Диск алмазный 1ADM-EPA-125', 'tools', 'шт', 'universal/090.jpg'),
  ('universal', 'universal.cutting_disc_luga_180', 'Диск отрезной LUGA 180', 'tools', 'шт', 'universal/017.jpg'),
  ('universal', 'universal.cutting_disc_epa_125', 'Диск отрезной EPA-125', 'tools', 'шт', 'universal/019.jpg'),
  ('universal', 'universal.saw_disc_epa_180', 'Диск пильный EPA 1PD-180', 'tools', 'шт', 'universal/027.jpg'),
  ('universal', 'universal.core_bit_25', 'Коронка алмазная 25 мм', 'tools', 'шт', 'universal/064.jpg'),
  ('universal', 'universal.core_bit_75', 'Коронка алмазная 75 мм', 'tools', 'шт', 'universal/065.jpg'),
  ('universal', 'universal.metal_drill_6', 'Сверло по металлу 6 мм', 'tools', 'шт', 'universal/010.jpg'),
  ('universal', 'universal.sds_drill_6x120', 'Бур по бетону SDS plus 6х120 Lit', 'tools', 'шт', 'universal/025.jpg'),
  ('universal', 'universal.sds_drill_10x350', 'Бур по бетону SDS plus 10х350 Lit', 'tools', 'шт', 'universal/026.jpg'),
  ('universal', 'universal.screwdriver_bit_ph2', 'Насадка для шуруповёрта PH2х65', 'tools', 'шт', 'universal/009.jpg'),
  ('universal', 'universal.screwdriver_06x4', 'Отвёртка 0,6х4', 'tools', 'шт', 'universal/011.jpg'),
  ('universal', 'universal.spatula_250', 'Шпатель 250 мм', 'tools', 'шт', 'universal/012.jpg'),
  ('universal', 'universal.spatula_400', 'Шпатель 400 мм', 'tools', 'шт', 'universal/013.jpg'),
  ('universal', 'universal.wrench_10', 'Ключ комбинированный 10 мм', 'tools', 'шт', 'universal/068.jpg'),
  ('universal', 'universal.wrench_19', 'Ключ комбинированный 19 мм', 'tools', 'шт', 'universal/069.jpg'),
  ('universal', 'universal.hammer_rubber', 'Молоток резиновый', 'tools', 'шт', 'universal/070.jpg'),
  ('universal', 'universal.hammer_steel_1kg', 'Молоток железный 1 кг Lit', 'tools', 'шт', 'universal/071.jpg'),
  ('universal', 'universal.utility_knife_18', 'Нож канцелярский 18 мм', 'tools', 'шт', 'universal/024.jpg'),
  ('universal', 'universal.utility_blades_18', 'Лезвия для канцелярского ножа 18 мм, 10 шт', 'tools', 'упак', 'universal/023.jpg'),
  ('universal', 'universal.tape_measure_5m', 'Рулетка 5 м Lit', 'tools', 'шт', 'universal/028.jpg'),
  ('universal', 'universal.tape_measure_10m', 'Рулетка 10 м Lit', 'tools', 'шт', 'universal/029.jpg'),
  ('universal', 'universal.foam_gun', 'Пистолет для монтажной пены', 'tools', 'шт', 'universal/034.jpg'),
  ('universal', 'universal.sealant_gun', 'Пистолет для герметика', 'tools', 'шт', 'universal/035.jpg'),
  ('universal', 'universal.builders_line', 'Леска строительная', 'tools', 'шт', 'universal/091.jpg'),
  ('universal', 'universal.welding_mask', 'Маска сварочная «хамелеон»', 'tools', 'шт', 'universal/095.jpg'),
  ('universal', 'universal.welding_electrodes_3', 'Электроды Арсенал 3 мм', 'tools', 'кг', 'universal/096.jpg'),
  ('universal', 'universal.switch_2g_flush', 'Выключатель внутренний 2-клавишный (белый)', 'electrical', 'шт', 'universal/031.jpg'),
  ('universal', 'universal.switch_2g_surface', 'Выключатель наружный 2-клавишный (белый)', 'electrical', 'шт', 'universal/030.jpg'),
  ('universal', 'universal.socket_2g_flush', 'Розетка внутренняя 2-местная (белая)', 'electrical', 'шт', 'universal/033.jpg'),
  ('universal', 'universal.socket_2g_surface', 'Розетка наружная 2-местная (белая)', 'electrical', 'шт', 'universal/032.jpg'),
  ('universal', 'universal.socket_box_ring', 'Кольцо-подрозетник', 'electrical', 'шт', 'universal/094.jpg'),
  ('universal', 'universal.led_lamp_10w', 'Лампочка светодиодная 10 Вт', 'electrical', 'шт', 'universal/037.jpg'),
  ('universal', 'universal.led_lamp_60w', 'Лампочка светодиодная 60 Вт', 'electrical', 'шт', 'universal/038.jpg'),
  ('universal', 'universal.lamp_holder', 'Патрон для ламп', 'electrical', 'шт', 'universal/040.jpg'),
  ('universal', 'universal.led_panel_recessed_square_24w', 'LED-панель встраиваемая, квадратная 24 Вт 6500K', 'electrical', 'шт', 'universal/043.jpg'),
  ('universal', 'universal.led_panel_recessed_round_24w', 'LED-панель встраиваемая, круглая 24 Вт 6500K', 'electrical', 'шт', 'universal/044.jpg'),
  ('universal', 'universal.led_panel_surface_square_24w', 'LED-панель накладная, квадратная 24 Вт 6500K', 'electrical', 'шт', 'universal/045.jpg'),
  ('universal', 'universal.led_panel_surface_round_24w', 'LED-панель накладная, круглая 24 Вт 6500K', 'electrical', 'шт', 'universal/042.jpg'),
  ('universal', 'universal.extension_block_3', 'Колодка удлинителя, 3 розетки, без кабеля', 'electrical', 'шт', 'universal/039.jpg'),
  ('universal', 'universal.plug_16a', 'Вилка электрическая турецкая, 16А 250В', 'electrical', 'шт', 'universal/041.jpg'),
  ('universal', 'universal.cable_pvs_2x15_white', 'Кабель медный ПВС 2х1,5, белый', 'electrical', 'м', 'universal/059.jpg'),
  ('universal', 'universal.cable_pvs_2x15_black', 'Кабель медный ПВС 2х1,5, чёрный', 'electrical', 'м', 'universal/060.jpg'),
  ('universal', 'universal.cable_pvs_2x25_black', 'Кабель медный ПВС 2х2,5, чёрный', 'electrical', 'м', 'universal/061.jpg'),
  ('universal', 'universal.insulating_tape', 'Изолента Vini Tape', 'electrical', 'шт', 'universal/058.jpg'),
  ('universal', 'universal.screws', 'Саморезы', 'fasteners', 'кг', 'universal/014.jpg'),
  ('universal', 'universal.screws_drill_16', 'Саморезы «семечки» 1,6 мм', 'fasteners', 'кг', 'universal/097.jpg'),
  ('universal', 'universal.screws_roofing', 'Саморезы кровельные', 'fasteners', 'кг', 'universal/076.jpg'),
  ('universal', 'universal.nails', 'Гвозди', 'fasteners', 'кг', 'universal/015.jpg'),
  ('universal', 'universal.bolts_galvanized', 'Болты оцинкованные', 'fasteners', 'кг', 'universal/050.jpg'),
  ('universal', 'universal.nuts_galvanized', 'Гайка оцинкованная', 'fasteners', 'кг', 'universal/051.jpg'),
  ('universal', 'universal.washers_galvanized', 'Шайба оцинкованная', 'fasteners', 'кг', 'universal/052.jpg'),
  ('universal', 'universal.anchor_bolt_10x120', 'Анкер-болт с гайкой 10х120', 'fasteners', 'шт', 'universal/053.jpg'),
  ('universal', 'universal.anchor_frame_10x112', 'Анкер рамный (под отвёртку) 10х112', 'fasteners', 'шт', 'universal/054.jpg'),
  ('universal', 'universal.dowel_6x60', 'Дюбель 6х60', 'fasteners', 'шт', 'universal/100.jpg'),
  ('universal', 'universal.dowel_umbrella_10x120', 'Дюбель-зонт 10х120 мм', 'fasteners', 'шт', 'universal/072.jpg'),
  ('universal', 'universal.dowel_screw_6x60', 'Дюбель-саморез 6х60', 'fasteners', 'кг', 'universal/073.jpg'),
  ('universal', 'universal.dowel_nail', 'Дюбель-гвоздь', 'fasteners', 'кг', 'universal/074.jpg'),
  ('universal', 'universal.powder_nails_27', 'Дюбель-гвозди для порохового пистолета 27 мм, 200 шт', 'fasteners', 'упак', 'universal/075.jpg'),
  ('universal', 'universal.cable_tie_white_250', 'Хомут нейлоновый белый 250 мм, 100 шт', 'fasteners', 'упак', 'universal/048.jpg'),
  ('universal', 'universal.cable_tie_black_250', 'Хомут нейлоновый чёрный 250 мм, 100 шт', 'fasteners', 'упак', 'universal/049.jpg'),
  ('universal', 'universal.padlock_70', 'Замок навесной 70 мм', 'fasteners', 'шт', 'universal/008.jpg'),
  ('universal', 'universal.rotband_25', 'Кнауф Ротбанд, 25 кг', 'mixes', 'мешок', 'universal/079.jpg'),
  ('universal', 'universal.fugen_25', 'Кнауф Фуген, 25 кг', 'mixes', 'мешок', 'universal/084.jpg'),
  ('universal', 'universal.tile_glue_megamix_22', 'Клей плиточный усиленный Megamix 22', 'mixes', 'мешок', 'universal/080.jpg'),
  ('universal', 'universal.putty_eleron_01', 'Шпатлёвка Элерон 01 для внутренних работ, 20 кг', 'mixes', 'мешок', 'universal/081.jpg'),
  ('universal', 'universal.putty_eleron_05', 'Шпатлёвка гипсовая Элерон 05, 20 кг', 'mixes', 'мешок', 'universal/083.jpg'),
  ('universal', 'universal.putty_eleron_001', 'Шпатлёвка суперфинишная Элерон 001', 'mixes', 'мешок', 'universal/082.jpg'),
  ('universal', 'universal.foam_tytan_65', 'Пена монтажная универсальная TYTAN 65', 'mixes', 'баллон', 'universal/077.jpg'),
  ('universal', 'universal.silicone_akfix_100e', 'Силикон универсальный прозрачный Akfix 100E', 'mixes', 'туба', 'universal/098.jpg'),
  ('universal', 'universal.glue_tytan_classic_fix', 'Клей монтажный TYTAN Classic Fix, 310 мл', 'mixes', 'туба', 'universal/099.jpg'),
  ('universal', 'universal.glue_akfix_705', 'Клей двухкомпонентный Akfix 705 (большой)', 'mixes', 'компл', 'universal/078.jpg'),
  ('universal', 'universal.pva_eron', 'Клей ПВА Эрон', 'mixes', 'кг', 'universal/004.jpg'),
  ('universal', 'universal.enamel_hayat_pf115', 'Краска Hayat PF-115 Emali', 'paints', 'кг', 'universal/005.jpg'),
  ('universal', 'universal.tint_palizh', 'Колер Palizh', 'paints', 'шт', 'universal/066.jpg'),
  ('universal', 'universal.tint_pufamix', 'Колер PUFAMIX, оригинал', 'paints', 'шт', 'universal/067.jpg'),
  ('universal', 'universal.solvent_646', 'Растворитель Б-646', 'paints', 'л', 'universal/055.jpg'),
  ('universal', 'universal.thinner', 'Разбавитель', 'paints', 'л', 'universal/056.jpg'),
  ('universal', 'universal.brush_3', 'Кисть для водоэмульсионных красок 3"', 'paints', 'шт', 'universal/046.jpg'),
  ('universal', 'universal.brush_4', 'Кисть для водоэмульсионных красок 4"', 'paints', 'шт', 'universal/047.jpg'),
  ('universal', 'universal.masking_film_180', 'Плёнка защитная с малярным скотчем, 180 см', 'paints', 'рулон', 'universal/003.jpg'),
  ('universal', 'universal.drywall_wall', 'Гипсокартон стеновой', 'finishing', 'лист', 'universal/085.jpg'),
  ('universal', 'universal.drywall_ceiling', 'Гипсокартон потолочный', 'finishing', 'лист', 'universal/086.jpg'),
  ('universal', 'universal.drywall_moisture', 'Гипсокартон стеновой влагостойкий', 'finishing', 'лист', 'universal/087.jpg'),
  ('universal', 'universal.tile_leveling_clip_14', 'СВП зажим 1,4 мм, 250 шт', 'finishing', 'упак', 'universal/062.jpg'),
  ('universal', 'universal.tile_leveling_wedge_14', 'СВП клин 1,4 мм, 100 шт', 'finishing', 'упак', 'universal/063.jpg'),
  ('universal', 'universal.roll_insulation_03', 'Изоляция рулонная (синтепон), завод 03', 'insulation', 'рулон', 'universal/088.jpg'),
  ('universal', 'universal.roll_insulation_05', 'Изоляция рулонная (синтепон), завод 05', 'insulation', 'рулон', 'universal/089.jpg'),
  ('universal', 'universal.film_black_06', 'Плёнка полиэтиленовая 0,6, чёрная', 'insulation', 'м', 'universal/092.jpg'),
  ('universal', 'universal.film_white_06', 'Плёнка полиэтиленовая 0,6, белая', 'insulation', 'м', 'universal/093.jpg');

INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path) VALUES
  ('plumbing', 'plumbing.adapter_coupling_female_25', 'VERO Адаптер-муфта комб. В/Р 25х1/2', 'plumbing', 'шт', 'plumbing/001.jpg'),
  ('plumbing', 'plumbing.adapter_coupling_male_25', 'VERO Адаптер-муфта комб. Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/002.jpg'),
  ('plumbing', 'plumbing.adapter_nipple_25_half', 'VERO Адаптер с накидной гайкой (ниппель) 25х1/2', 'plumbing', 'шт', 'plumbing/003.jpg'),
  ('plumbing', 'plumbing.double_elbow_bracket_female_20', 'VERO Двойной отвод с креплением В/Р 20х15', 'plumbing', 'шт', 'plumbing/004.jpg'),
  ('plumbing', 'plumbing.double_elbow_bracket_male_20', 'VERO Двойной отвод с креплением Н/Р 20х15', 'plumbing', 'шт', 'plumbing/005.jpg'),
  ('plumbing', 'plumbing.plug_25', 'VERO Заглушка 25', 'plumbing', 'шт', 'plumbing/006.jpg'),
  ('plumbing', 'plumbing.clip_25', 'VERO Клипса 25', 'plumbing', 'шт', 'plumbing/007.jpg'),
  ('plumbing', 'plumbing.cross_90_20', 'VERO Крестовина 90° 20', 'plumbing', 'шт', 'plumbing/008.jpg'),
  ('plumbing', 'plumbing.clamp_metal_45_52', 'VERO Хомут металлический 45-52 (1 1/2")', 'plumbing', 'шт', 'plumbing/009.jpg'),
  ('plumbing', 'plumbing.coupling_25', 'VERO Муфта 25', 'plumbing', 'шт', 'plumbing/010.jpg'),
  ('plumbing', 'plumbing.bypass_25', 'VERO Обвод 25', 'plumbing', 'шт', 'plumbing/011.jpg'),
  ('plumbing', 'plumbing.elbow_90_25', 'VERO Отвод 90° 25', 'plumbing', 'шт', 'plumbing/012.jpg'),
  ('plumbing', 'plumbing.elbow_wall_female_20', 'VERO Отвод с настенным креплением В/Р 20', 'plumbing', 'шт', 'plumbing/013.jpg'),
  ('plumbing', 'plumbing.elbow_wall_male_20', 'VERO Отвод с настенным креплением Н/Р 20', 'plumbing', 'шт', 'plumbing/014.jpg'),
  ('plumbing', 'plumbing.reducer_32_20', 'VERO Переходник 32-20', 'plumbing', 'шт', 'plumbing/015.jpg'),
  ('plumbing', 'plumbing.elbow_45_25', 'VERO Полуотвод 25', 'plumbing', 'шт', 'plumbing/016.jpg'),
  ('plumbing', 'plumbing.union_female_25_three_quarter', 'VERO Ракор В/Р 25х3/4', 'plumbing', 'шт', 'plumbing/017.jpg'),
  ('plumbing', 'plumbing.union_male_25_half', 'VERO Ракор Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/018.jpg'),
  ('plumbing', 'plumbing.tee_25', 'VERO Тройник 25', 'plumbing', 'шт', 'plumbing/019.jpg'),
  ('plumbing', 'plumbing.tee_female_20_half', 'VERO Тройник комб. с В/Р 20х1/2', 'plumbing', 'шт', 'plumbing/020.jpg'),
  ('plumbing', 'plumbing.tee_male_25_half', 'VERO Тройник комб. с Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/021.jpg'),
  ('plumbing', 'plumbing.tee_reducing_32_20_32', 'VERO Тройник переходник 32-20-32', 'plumbing', 'шт', 'plumbing/022.jpg'),
  ('plumbing', 'plumbing.radiator_valve_angle_20', 'VERO Угловой кран для радиатора 20х1/2', 'plumbing', 'шт', 'plumbing/023.jpg'),
  ('plumbing', 'plumbing.radiator_valve_angle_20_import', 'VERO Угловой кран для радиатора 20х1/2 (импорт)', 'plumbing', 'шт', 'plumbing/024.jpg'),
  ('plumbing', 'plumbing.elbow_female_25_half', 'VERO Угол В/Р 25х1/2', 'plumbing', 'шт', 'plumbing/025.jpg'),
  ('plumbing', 'plumbing.elbow_male_25_half', 'VERO Угол Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/026.jpg'),
  ('plumbing', 'plumbing.elbow_nipple_25_three_quarter', 'VERO Угол с накидной гайкой (ниппель) 25х3/4', 'plumbing', 'шт', 'plumbing/027.jpg'),
  ('plumbing', 'plumbing.filter_25_brass', 'VERO Фильтр 25 «мама» (латунь)', 'plumbing', 'шт', 'plumbing/028.jpg'),
  ('plumbing', 'plumbing.ball_valve_20', 'VERO Шаровой кран 20', 'plumbing', 'шт', 'plumbing/029.jpg'),
  ('plumbing', 'plumbing.ball_valve_20_eco', 'VERO Шаровой кран 20 ECO', 'plumbing', 'шт', 'plumbing/030.jpg'),
  ('plumbing', 'plumbing.cistern_valve_dual_flush', 'Механизм нижний с двухрежимным выпуском', 'plumbing', 'шт', 'plumbing/031.jpg'),
  ('plumbing', 'plumbing.cistern_float_side', 'Поплавок боковой (пластмасса)', 'plumbing', 'шт', 'plumbing/032.jpg'),
  ('plumbing', 'plumbing.toilet_corrugation', 'Гофра для унитаза', 'plumbing', 'шт', 'plumbing/033.jpg'),
  ('plumbing', 'plumbing.toilet_corrugation_angle', 'Гофра для унитаза угловая', 'plumbing', 'шт', 'plumbing/034.jpg'),
  ('plumbing', 'plumbing.toilet_seat_fixing', 'Крепление для сиденья унитаза', 'plumbing', 'шт', 'plumbing/035.jpg'),
  ('plumbing', 'plumbing.siphon_rubber_seal', 'Резина для сифона («вонючка»)', 'plumbing', 'шт', 'plumbing/036.jpg'),
  ('plumbing', 'plumbing.siphon_outlet_head', 'Выпуск для сифона (головка)', 'plumbing', 'шт', 'plumbing/037.jpg'),
  ('plumbing', 'plumbing.siphon_bowl_round_overflow', 'Сифон с тазиком и круглым переливом', 'plumbing', 'шт', 'plumbing/038.jpg'),
  ('plumbing', 'plumbing.toilet_seat_cover', 'Сиденье с крышкой для унитаза', 'plumbing', 'шт', 'plumbing/039.jpg'),
  ('plumbing', 'plumbing.siphon_bath', 'Сифон для ванны', 'plumbing', 'шт', 'plumbing/040.jpg'),
  ('plumbing', 'plumbing.siphon_sink_eco', 'Сифон для мойки с выпуском и переливом ЭКО', 'plumbing', 'шт', 'plumbing/041.jpg'),
  ('plumbing', 'plumbing.drain_shower_side_plastic', 'Трап сливной для душа, боковой (пластик)', 'plumbing', 'шт', 'plumbing/042.jpg'),
  ('plumbing', 'plumbing.drain_shower_straight_plastic', 'Трап сливной для душа, прямой (пластик)', 'plumbing', 'шт', 'plumbing/043.jpg'),
  ('plumbing', 'plumbing.drain_aqua_ss28', 'Трап AQUA 10х10 SS-28', 'plumbing', 'шт', 'plumbing/044.jpg'),
  ('plumbing', 'plumbing.drain_aqua_12pro', 'Трап 12 PRO AQUA 10х10 (никель)', 'plumbing', 'шт', 'plumbing/045.jpg'),
  ('plumbing', 'plumbing.drain_aqua_tile', 'Трап под кафель AQUA 10х10 (никель)', 'plumbing', 'шт', 'plumbing/046.jpg'),
  ('plumbing', 'plumbing.washer_drain_hose_190', 'Сливной шланг для стиральной машины 190 мм', 'plumbing', 'шт', 'plumbing/047.jpg'),
  ('plumbing', 'plumbing.washer_drain_hose_290', 'Сливной шланг для стиральной машины 290 мм', 'plumbing', 'шт', 'plumbing/048.jpg'),
  ('plumbing', 'plumbing.anti_vibration_pads', 'Антивибрационные подставки', 'plumbing', 'шт', 'plumbing/049.jpg'),
  ('plumbing', 'plumbing.washer_inlet_hose_25', 'Шланг наливной 2,5 м', 'plumbing', 'шт', 'plumbing/050.jpg'),
  ('plumbing', 'plumbing.mixer_cartridge', 'Механизм для джойстика', 'plumbing', 'шт', 'plumbing/051.jpg'),
  ('plumbing', 'plumbing.tap_valve_square_brass', 'Кран-букса квадрат (латунь), красная', 'plumbing', 'шт', 'plumbing/052.jpg'),
  ('plumbing', 'plumbing.tap_handle_cross_new', 'Барашек крестовой NEW', 'plumbing', 'шт', 'plumbing/053.jpg'),
  ('plumbing', 'plumbing.mixer_bracket', 'Лапка смесителя', 'plumbing', 'шт', 'plumbing/054.jpg'),
  ('plumbing', 'plumbing.boou_fixator_zl115', 'BOOU Фиксатор ZL-115', 'plumbing', 'шт', 'plumbing/055.jpg'),
  ('plumbing', 'plumbing.spout_filter_male', 'Фильтр для гусака с сальником (н/р)', 'plumbing', 'шт', 'plumbing/056.jpg'),
  ('plumbing', 'plumbing.mixer_mic_aqua_19808', 'Смеситель-микрофон гусак серый AQUA 19808-27', 'plumbing', 'шт', 'plumbing/057.jpg'),
  ('plumbing', 'plumbing.mixer_mic_cheap', 'Смеситель-микрофон гусак (дешёвый)', 'plumbing', 'шт', 'plumbing/058.jpg'),
  ('plumbing', 'plumbing.shower_hose_aqua_aq01', 'Душевой шланг AQUA 1,5-1,8 м AQ-01', 'plumbing', 'шт', 'plumbing/059.jpg'),
  ('plumbing', 'plumbing.hose_reinforced_mm_alfa_80', 'Шланг армированный м/м ALFA 80 см', 'plumbing', 'шт', 'plumbing/060.jpg'),
  ('plumbing', 'plumbing.hose_reinforced_ms_alfa_70', 'Шланг армированный м/с ALFA 70 см', 'plumbing', 'шт', 'plumbing/061.jpg'),
  ('plumbing', 'plumbing.hose_water_boou_100', 'Шланг для воды BOOU м/м 100 см', 'plumbing', 'шт', 'plumbing/062.jpg'),
  ('plumbing', 'plumbing.hose_mixer_boou_80', 'Шланг для смесителя BOOU «ёлка» 80 см', 'plumbing', 'шт', 'plumbing/063.jpg'),
  ('plumbing', 'plumbing.shower_head_aqua_r50', 'Лейка AQUA AQ-R50', 'plumbing', 'шт', 'plumbing/064.jpg'),
  ('plumbing', 'plumbing.thermoflex_28x6_red', 'Термофлекс 28х6/2 красный', 'plumbing', 'шт', 'plumbing/065.jpg'),
  ('plumbing', 'plumbing.thermoflex_28x6_blue', 'Термофлекс 28х6/2 синий', 'plumbing', 'шт', 'plumbing/066.jpg'),
  ('plumbing', 'plumbing.sewer_pipe_100_3m', 'VERO Канализационная труба 2,2 мм — 100/3 м', 'plumbing', 'шт', 'plumbing/067.jpg'),
  ('plumbing', 'plumbing.sewer_pipe_50_3m', 'VERO Канализационная труба 2,2 мм — 50/3 м', 'plumbing', 'шт', 'plumbing/068.jpg'),
  ('plumbing', 'plumbing.sewer_pipe_75_3m', 'VERO Канализационная труба 2,2 мм — 75/3 м', 'plumbing', 'шт', 'plumbing/069.jpg'),
  ('plumbing', 'plumbing.sewer_pipe_150_3m', 'VERO Канализационная труба 3,2 мм — 150/3 м', 'plumbing', 'шт', 'plumbing/070.jpg'),
  ('plumbing', 'plumbing.sewer_clip_100', 'VERO (к) Клипса 100', 'plumbing', 'шт', 'plumbing/071.jpg'),
  ('plumbing', 'plumbing.sewer_clip_50', 'VERO (к) Клипса 50', 'plumbing', 'шт', 'plumbing/072.jpg'),
  ('plumbing', 'plumbing.sewer_coupling_110', 'VERO (к) Муфта 110', 'plumbing', 'шт', 'plumbing/073.jpg'),
  ('plumbing', 'plumbing.sewer_elbow_100', 'VERO (к) Отвод 100', 'plumbing', 'шт', 'plumbing/074.jpg'),
  ('plumbing', 'plumbing.sewer_elbow_45_100', 'VERO (к) Полуотвод 100', 'plumbing', 'шт', 'plumbing/075.jpg'),
  ('plumbing', 'plumbing.sewer_tee_100_100', 'VERO (к) Тройник 100/100 90°', 'plumbing', 'шт', 'plumbing/076.jpg'),
  ('plumbing', 'plumbing.sewer_tee_100_50', 'VERO (к) Тройник 100/50 90°', 'plumbing', 'шт', 'plumbing/077.jpg'),
  ('plumbing', 'plumbing.barrel_nipple_15_cheap', 'Бочонок (дешёвый) 15', 'plumbing', 'шт', 'plumbing/078.jpg'),
  ('plumbing', 'plumbing.barrel_nipple_15_brass', 'Бочонок латунный (сальник) 15', 'plumbing', 'шт', 'plumbing/079.jpg'),
  ('plumbing', 'plumbing.plug_20_male_cheap', 'Заглушка 20 М (дешёвая)', 'plumbing', 'шт', 'plumbing/080.jpg'),
  ('plumbing', 'plumbing.calso_15x20_cheap', 'Кальсо (дешёвое) 15х20 М-П', 'plumbing', 'шт', 'plumbing/081.jpg'),
  ('plumbing', 'plumbing.calso_15x20_steel', 'Кальсо нержавейка 15х20 М-П', 'plumbing', 'шт', 'plumbing/082.jpg'),
  ('plumbing', 'plumbing.coupling_20_steel', 'Муфта нержавейка 20 (304)', 'plumbing', 'шт', 'plumbing/083.jpg'),
  ('plumbing', 'plumbing.elbow_15_brass', 'Отвод 15 М-М (латунный)', 'plumbing', 'шт', 'plumbing/084.jpg'),
  ('plumbing', 'plumbing.elbow_15_steel', 'Отвод нержавейка 15 (304) М-П', 'plumbing', 'шт', 'plumbing/085.jpg'),
  ('plumbing', 'plumbing.reducer_20x25_steel', 'Переходник нержавейка 20х25 П-П', 'plumbing', 'шт', 'plumbing/086.jpg'),
  ('plumbing', 'plumbing.tee_15_mmm_brass', 'Тройник 15 М-М-М (латунный)', 'plumbing', 'шт', 'plumbing/087.jpg'),
  ('plumbing', 'plumbing.tee_15_mmf_brass', 'Тройник 15 М-М-П (латунный)', 'plumbing', 'шт', 'plumbing/088.jpg'),
  ('plumbing', 'plumbing.nipple_15_male_cheap', 'Штуцер 15 н/р (дешёвый)', 'plumbing', 'шт', 'plumbing/089.jpg'),
  ('plumbing', 'plumbing.eccentric_brass_90', 'Эксцентрик (латунный) 90', 'plumbing', 'шт', 'plumbing/090.jpg'),
  ('plumbing', 'plumbing.extension_15', 'Удлинитель 1,5 см', 'plumbing', 'шт', 'plumbing/091.jpg'),
  ('plumbing', 'plumbing.coupling_16', 'Муфта 16', 'plumbing', 'шт', 'plumbing/092.jpg'),
  ('plumbing', 'plumbing.elbow_16_ktm', 'Отвод (латунный) 16 КТМ', 'plumbing', 'шт', 'plumbing/093.jpg'),
  ('plumbing', 'plumbing.tee_16_ktm', 'Тройник 16 КТМ', 'plumbing', 'шт', 'plumbing/094.jpg'),
  ('plumbing', 'plumbing.boou_mixer_shower_b8156_5s', 'BOOU Смеситель для душа B8156-5S (Ж)', 'plumbing', 'шт', 'plumbing/095.jpg'),
  ('plumbing', 'plumbing.boou_mixer_riser_7195', 'BOOU Смеситель стояк 7195-75 (Ж)', 'plumbing', 'шт', 'plumbing/096.jpg'),
  ('plumbing', 'plumbing.boou_mixer_mic_bz9184j', 'BOOU Смеситель-микрофон BZ9184J-E367 (Ж)', 'plumbing', 'шт', 'plumbing/097.jpg'),
  ('plumbing', 'plumbing.boou_mixer_b8156_14a', 'BOOU Смеситель B8156-14A (Ж)', 'plumbing', 'шт', 'plumbing/098.jpg'),
  ('plumbing', 'plumbing.mixer_electric_alfa', 'Электрический смеситель ALFA', 'plumbing', 'шт', 'plumbing/099.jpg'),
  ('plumbing', 'plumbing.boou_mixer_bidet_b8246', 'BOOU Смеситель «тахорат» B8246-4AH-F805 (Ж)', 'plumbing', 'шт', 'plumbing/100.jpg');

-- **only five, deliberately**: an owner must price EVERY row to be ranked at all, so a template
-- holding an item a shop does not stock guarantees that shop never appears.
INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path) VALUES
  ('wood', 'wood.beam_50x100', 'Брус 50х100х6000', 'lumber', 'шт', 'wood/001.jpg'),
  ('wood', 'wood.board_25x150', 'Доска 25х150х6000', 'lumber', 'шт', 'wood/002.jpg'),
  ('wood', 'wood.batten_30x40', 'Таб-рейка 30х40', 'lumber', 'м', 'wood/003.jpg'),
  ('wood', 'wood.plywood_18', 'Фанера 18 мм, 1525х1525', 'lumber', 'лист', 'wood/004.jpg'),
  ('wood', 'wood.rafter_50x150', 'Стропила 50х150х6000', 'lumber', 'шт', 'wood/005.jpg');

INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path) VALUES
  ('wallpaper', 'wallpaper.premium_ru', 'Обои премиум (Россия)', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.premium_cn', 'Обои премиум (Китай)', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.premium_uz', 'Обои премиум (Узбекистан)', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.standard_uz_1', 'Обои стандарт (Узбекистан) №1', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.standard_uz_2', 'Обои стандарт (Узбекистан) №2', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.standard_ru_1', 'Обои стандарт (Россия) №1', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.standard_ru_2', 'Обои стандарт (Россия) №2', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.econom_uz', 'Обои эконом (Узбекистан)', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.econom_cn_1', 'Обои эконом (Китай) №1', 'finishing', 'рулон', NULL),
  ('wallpaper', 'wallpaper.econom_cn_2', 'Обои эконом (Китай) №2', 'finishing', 'рулон', NULL);

CREATE TABLE support_messages (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    from_support BOOLEAN NOT NULL DEFAULT FALSE,
    body TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_support_messages_thread ON support_messages (user_id, id);

-- Which support conversations an admin has already looked at. Nothing to do with `unanswered`,
-- which is derived in SQL: reading a thread does not answer anybody.
--
-- **a watermark, not a flag.** message ids only go up, so "unread" stays derived - COUNT(*) WHERE
-- id > last_read_id - and a message arriving a second later is unread by arithmetic rather than by
-- something remembering to set a bit. keyed per admin, because "seen" is a fact about a person.
CREATE TABLE IF NOT EXISTS support_thread_reads (
    -- who did the reading
    admin_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- a thread *is* one user's messages, so it is addressed by user id here as it is in the api
    thread_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    last_read_id   BIGINT      NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (admin_id, thread_user_id)
);

-- no second index on purpose: the primary key's leading column already serves the inbox's read

-- What a category's basket cost, one row per market per day.
--
-- **the only fact in this product that cannot be recomputed**: shop_basket_index always answers
-- about *now*, so the moment an owner retypes a price, what the basket cost yesterday is gone.
--
-- keyed by (day, category) so the hourly upsert is idempotent - a server restarted at the wrong
-- moment would otherwise skip whole days. a day with no row is a day the server was not running,
-- and the chart draws the gap: a zero would claim the market was free.
CREATE TABLE IF NOT EXISTS basket_history (
    day        DATE   NOT NULL,
    category   TEXT   NOT NULL,

    -- how many shops were in the comparison that day. it is what makes an average readable later:
    -- a jump from 3 shops to 9 explains a move that would otherwise look like a price change.
    shops      INT    NOT NULL,

    avg_basket BIGINT NOT NULL,
    min_basket BIGINT NOT NULL,
    max_basket BIGINT NOT NULL,

    PRIMARY KEY (day, category)
);

-- no second index on purpose: the primary key's leading column serves the range scan on `day`

-- One row per shop that has priced its entire category template - the Basket Price Index.
--
-- **a table kept current by triggers, not a view recomputed on every read.** the read side is every
-- customer opening the map; the write side is an owner retyping a price. so the arithmetic moves to
-- the write and the read becomes a primary-key lookup.
--
-- triggers rather than Go, because the writes that can move this number are spread across shop
-- creation, product edits, three template-sync statements and two cascade chains no Go code runs at
-- all. an invariant that many call sites must remember is one the next call site breaks.
CREATE TABLE shop_basket_index (
    shop_id       BIGINT PRIMARY KEY REFERENCES shops(id) ON DELETE CASCADE,

    -- copied from shops.category rather than joined for it. This is what lets a refresh find its
    -- own stale rows: when a shop moves markets, the row to delete is the one filed under the
    -- category the shop *used* to be in, and a join to shops would only ever report the new one.
    shop_category VARCHAR(30) NOT NULL,

    basket_price  BIGINT NOT NULL,
    price_index   BIGINT NOT NULL,

    -- not read by any query. it is here so that a stale index is diagnosable from psql - "when was
    -- this last agreed with products?" has no answer otherwise, and a cache whose staleness cannot
    -- be observed is a cache you end up not trusting.
    updated_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- a refresh works one market at a time; without this it would scan the whole table to find them
CREATE INDEX idx_shop_basket_index_category ON shop_basket_index (shop_category);

-- **a row exists only for a shop that has priced its entire template** and is not excluded by an
-- admin, which is why every read LEFT JOINs this - a shop with an unpriced row still has to open, it
-- just opens without a badge. the rankings are the exception and INNER JOIN.
--
-- whole-market and never per-shop: price_index divides a shop's basket by its market's average, so
-- one owner retyping one price moves the divisor and every competitor's score with it.
--
-- **the advisory lock is not decoration.** two owners pricing at the same moment would otherwise
-- both average a snapshot taken before the other committed, and the second writer would overwrite
-- the first with a number that no longer included it - wrong until the next unrelated write.
CREATE OR REPLACE FUNCTION refresh_basket_index(p_category text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('shop_basket_index'), hashtext(p_category));

    -- one statement, so the aggregate is computed once and the delete and the upsert cannot
    -- disagree about it. The two write sets are disjoint by construction - `dropped` is precisely
    -- the rows *not* in `ranked` - which is what makes it safe to write the same table from a CTE
    -- and from the main statement.
    WITH basket AS (
        SELECT p.shop_id,
               SUM(p.price) AS basket_price
        FROM products p
        JOIN shops s ON s.id = p.shop_id
        WHERE p.template_key IS NOT NULL
          AND s.category = p_category
          AND NOT s.excluded_from_index
        GROUP BY p.shop_id
        HAVING COUNT(p.price) = COUNT(*)
    ),
    market AS (
        SELECT AVG(basket_price) AS market_basket FROM basket
    ),
    ranked AS (
        SELECT b.shop_id,
               b.basket_price::bigint                                AS basket_price,
               ROUND(b.basket_price / m.market_basket * 100)::bigint AS price_index
        FROM basket b
        CROSS JOIN market m
        WHERE m.market_basket > 0
    ),
    dropped AS (
        DELETE FROM shop_basket_index bi
        WHERE bi.shop_category = p_category
          AND NOT EXISTS (SELECT 1 FROM ranked r WHERE r.shop_id = bi.shop_id)
    )
    INSERT INTO shop_basket_index (shop_id, shop_category, basket_price, price_index, updated_at)
    SELECT r.shop_id, p_category, r.basket_price, r.price_index, CURRENT_TIMESTAMP
    FROM ranked r
    ON CONFLICT (shop_id) DO UPDATE
        SET shop_category = EXCLUDED.shop_category,
            basket_price  = EXCLUDED.basket_price,
            price_index   = EXCLUDED.price_index,
            updated_at    = EXCLUDED.updated_at
        -- an unchanged row is not rewritten: no new tuple, no WAL, no work for autovacuum later.
        -- This is what makes a busy market cheap rather than expensive - the bigger it gets, the
        -- less one price moves the average, so the more rows round to the index they already had.
        WHERE shop_basket_index.basket_price  IS DISTINCT FROM EXCLUDED.basket_price
           OR shop_basket_index.price_index   IS DISTINCT FROM EXCLUDED.price_index
           OR shop_basket_index.shop_category IS DISTINCT FROM EXCLUDED.shop_category;
END;
$$;

-- rows appeared or disappeared in products.
--
-- **statement-level with a transition table, not FOR EACH ROW**: seeding a shop writes a hundred
-- rows at once, and a row trigger would recompute the market a hundred times.
--
-- **the EXISTS guard is what keeps shop creation cheap**: inserting an *unpriced* template row can
-- only ever take a shop out of the comparison, never put one in, so a shop with no row here yet has
-- nothing to recompute. only sound for INSERT - deleting an unpriced row is how a basket completes.
CREATE OR REPLACE FUNCTION basket_index_after_products() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    cat text;
BEGIN
    FOR cat IN
        SELECT DISTINCT s.category
        FROM changed c
        JOIN shops s ON s.id = c.shop_id
        WHERE c.template_key IS NOT NULL
          AND (TG_OP = 'DELETE'
               OR c.price IS NOT NULL
               OR EXISTS (SELECT 1 FROM shop_basket_index bi WHERE bi.shop_id = c.shop_id))
        -- so that a statement spanning two markets always locks them in the same order as any other
        ORDER BY 1
    LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;

    RETURN NULL;
END;
$$;

-- an existing product row changed. separate from the function above because it needs *both*
-- transition tables: the index is a function of exactly three columns, so an update that leaves
-- shop_id, template_key and price alone cannot move it.
--
-- not a hypothetical saving - AdminSyncTemplateUpdate rewrites names and photos across a whole
-- market at once, and photographing an обои slot writes image_path on a template row.
CREATE OR REPLACE FUNCTION basket_index_after_product_update() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    cat text;
BEGIN
    FOR cat IN
        SELECT DISTINCT s.category
        FROM changed_new n
        JOIN changed_old o ON o.id = n.id
        JOIN shops s ON s.id = n.shop_id
        WHERE (n.template_key IS NOT NULL OR o.template_key IS NOT NULL)
          AND (n.price       IS DISTINCT FROM o.price
            OR n.template_key IS DISTINCT FROM o.template_key
            OR n.shop_id      IS DISTINCT FROM o.shop_id)
        ORDER BY 1
    LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;

    RETURN NULL;
END;
$$;

-- a shop left a market, or an admin flipped excluded_from_index. the cascade takes its own row, but
-- the shop was one of the numbers in its market's average, so every *remaining* index moved too.
--
-- it refreshes every market rather than working out which: four categories, both events rare, and
-- the alternative needs a different transition table for a delete than for an update.
CREATE OR REPLACE FUNCTION basket_index_refresh_all() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    cat text;
BEGIN
    FOR cat IN SELECT DISTINCT category FROM shops ORDER BY 1 LOOP
        PERFORM refresh_basket_index(cat);
    END LOOP;

    RETURN NULL;
END;
$$;

-- three triggers because a trigger with transition tables may name exactly one event
CREATE TRIGGER products_basket_index_insert
    AFTER INSERT ON products
    REFERENCING NEW TABLE AS changed
    FOR EACH STATEMENT EXECUTE FUNCTION basket_index_after_products();

CREATE TRIGGER products_basket_index_delete
    AFTER DELETE ON products
    REFERENCING OLD TABLE AS changed
    FOR EACH STATEMENT EXECUTE FUNCTION basket_index_after_products();

CREATE TRIGGER products_basket_index_update
    AFTER UPDATE ON products
    REFERENCING OLD TABLE AS changed_old NEW TABLE AS changed_new
    FOR EACH STATEMENT EXECUTE FUNCTION basket_index_after_product_update();

-- AFTER, so the cascaded products are already gone when the markets recompute. a foreign key
-- cascade *is* a row trigger, and statement triggers fire after every row trigger of the statement.
CREATE TRIGGER shops_basket_index_delete
    AFTER DELETE ON shops
    FOR EACH STATEMENT EXECUTE FUNCTION basket_index_refresh_all();

-- an admin flipped the exclusion flag (see the shops.excluded_from_index column above).
CREATE TRIGGER shops_basket_index_excluded
    AFTER UPDATE OF excluded_from_index ON shops
    FOR EACH STATEMENT EXECUTE FUNCTION basket_index_refresh_all();

-- TRUNCATE fires none of the triggers above, so without this `TRUNCATE products` would leave a full
-- index describing baskets that no longer exist. the whole argument for putting this rule in the
-- database is that it holds for every writer, and a hole that only opens in psql is still a hole.
CREATE TRIGGER products_basket_index_truncate
    AFTER TRUNCATE ON products
    FOR EACH STATEMENT EXECUTE FUNCTION basket_index_refresh_all();
