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

CREATE TABLE support_messages (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    from_support BOOLEAN NOT NULL DEFAULT FALSE,
    body TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_support_messages_thread ON support_messages (user_id, id);

CREATE VIEW shop_basket_index AS
WITH basket AS (
    SELECT p.shop_id,
           s.category   AS shop_category,
           SUM(p.price) AS basket_price
    FROM products p
    JOIN shops s ON s.id = p.shop_id
    WHERE p.template_key IS NOT NULL
    GROUP BY p.shop_id, s.category
    HAVING COUNT(p.price) = COUNT(*)
),
market AS (
    SELECT shop_category,
           AVG(basket_price) AS market_basket
    FROM basket
    GROUP BY shop_category
)
SELECT b.shop_id,
       b.basket_price::bigint                                AS basket_price,
       ROUND(b.basket_price / m.market_basket * 100)::bigint AS price_index
FROM basket b
JOIN market m ON m.shop_category = b.shop_category
WHERE m.market_basket > 0;

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
  ('plumbing', 'plumbing.adapter_coupling_female_20', 'VERO Адаптер-муфта комб. В/Р 20х1/2', 'plumbing', 'шт', 'plumbing/001.jpg'),
  ('plumbing', 'plumbing.adapter_coupling_female_25', 'VERO Адаптер-муфта комб. В/Р 25х1/2', 'plumbing', 'шт', 'plumbing/002.jpg'),
  ('plumbing', 'plumbing.adapter_coupling_male_20', 'VERO Адаптер-муфта комб. Н/Р 20х1/2', 'plumbing', 'шт', 'plumbing/003.jpg'),
  ('plumbing', 'plumbing.adapter_coupling_male_25', 'VERO Адаптер-муфта комб. Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/004.jpg'),
  ('plumbing', 'plumbing.adapter_union_nut_25_half', 'VERO Адаптер с накидной гайкой 25х1/2 (V-2)', 'plumbing', 'шт', 'plumbing/005.jpg'),
  ('plumbing', 'plumbing.adapter_union_nut_25_three_quarter', 'VERO Адаптер с накидной гайкой 25х3/4 (V-2)', 'plumbing', 'шт', 'plumbing/006.jpg'),
  ('plumbing', 'plumbing.adapter_nipple_25_half', 'VERO Адаптер с накидной гайкой (ниппель) 25х1/2', 'plumbing', 'шт', 'plumbing/007.jpg'),
  ('plumbing', 'plumbing.double_elbow_bracket_female_20', 'VERO Двойной отвод с креплением В/Р 20х15', 'plumbing', 'шт', 'plumbing/008.jpg'),
  ('plumbing', 'plumbing.double_elbow_bracket_male_20', 'VERO Двойной отвод с креплением Н/Р 20х15', 'plumbing', 'шт', 'plumbing/009.jpg'),
  ('plumbing', 'plumbing.plug_20', 'VERO Заглушка 20', 'plumbing', 'шт', 'plumbing/010.jpg'),
  ('plumbing', 'plumbing.plug_25', 'VERO Заглушка 25', 'plumbing', 'шт', 'plumbing/011.jpg'),
  ('plumbing', 'plumbing.clip_20', 'VERO Клипса 20', 'plumbing', 'шт', 'plumbing/012.jpg'),
  ('plumbing', 'plumbing.clip_25', 'VERO Клипса 25', 'plumbing', 'шт', 'plumbing/013.jpg'),
  ('plumbing', 'plumbing.radiator_valve_straight_20', 'VERO Кран для радиатора прямой 20х1/2', 'plumbing', 'шт', 'plumbing/014.jpg'),
  ('plumbing', 'plumbing.cross_90_20', 'VERO Крестовина 90° 20', 'plumbing', 'шт', 'plumbing/015.jpg'),
  ('plumbing', 'plumbing.clamp_metal_20_24', 'VERO Хомут металлический 20-24 (1/2")', 'plumbing', 'шт', 'plumbing/016.jpg'),
  ('plumbing', 'plumbing.clamp_metal_45_52', 'VERO Хомут металлический 45-52 (1 1/2")', 'plumbing', 'шт', 'plumbing/017.jpg'),
  ('plumbing', 'plumbing.coupling_20', 'VERO Муфта 20', 'plumbing', 'шт', 'plumbing/018.jpg'),
  ('plumbing', 'plumbing.coupling_25', 'VERO Муфта 25', 'plumbing', 'шт', 'plumbing/019.jpg'),
  ('plumbing', 'plumbing.bypass_20', 'VERO Обвод 20', 'plumbing', 'шт', 'plumbing/020.jpg'),
  ('plumbing', 'plumbing.bypass_25', 'VERO Обвод 25', 'plumbing', 'шт', 'plumbing/021.jpg'),
  ('plumbing', 'plumbing.elbow_90_20', 'VERO Отвод 90° 20', 'plumbing', 'шт', 'plumbing/022.jpg'),
  ('plumbing', 'plumbing.elbow_90_25', 'VERO Отвод 90° 25', 'plumbing', 'шт', 'plumbing/023.jpg'),
  ('plumbing', 'plumbing.elbow_wall_female_20', 'VERO Отвод с настенным креплением В/Р 20', 'plumbing', 'шт', 'plumbing/024.jpg'),
  ('plumbing', 'plumbing.elbow_wall_female_25', 'VERO Отвод с настенным креплением В/Р 25', 'plumbing', 'шт', 'plumbing/025.jpg'),
  ('plumbing', 'plumbing.elbow_wall_male_20', 'VERO Отвод с настенным креплением Н/Р 20', 'plumbing', 'шт', 'plumbing/026.jpg'),
  ('plumbing', 'plumbing.elbow_wall_male_25', 'VERO Отвод с настенным креплением Н/Р 25', 'plumbing', 'шт', 'plumbing/027.jpg'),
  ('plumbing', 'plumbing.reducer_25_20', 'VERO Переходник 25-20', 'plumbing', 'шт', 'plumbing/028.jpg'),
  ('plumbing', 'plumbing.reducer_32_20', 'VERO Переходник 32-20', 'plumbing', 'шт', 'plumbing/029.jpg'),
  ('plumbing', 'plumbing.elbow_45_20', 'VERO Полуотвод 20', 'plumbing', 'шт', 'plumbing/030.jpg'),
  ('plumbing', 'plumbing.elbow_45_25', 'VERO Полуотвод 25', 'plumbing', 'шт', 'plumbing/031.jpg'),
  ('plumbing', 'plumbing.union_female_20_half', 'VERO Ракор В/Р 20х1/2', 'plumbing', 'шт', 'plumbing/032.jpg'),
  ('plumbing', 'plumbing.union_female_25_half', 'VERO Ракор В/Р 25х1/2', 'plumbing', 'шт', 'plumbing/033.jpg'),
  ('plumbing', 'plumbing.union_female_25_three_quarter', 'VERO Ракор В/Р 25х3/4', 'plumbing', 'шт', 'plumbing/034.jpg'),
  ('plumbing', 'plumbing.union_male_20_half', 'VERO Ракор Н/Р 20х1/2', 'plumbing', 'шт', 'plumbing/035.jpg'),
  ('plumbing', 'plumbing.union_male_25_half', 'VERO Ракор Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/036.jpg'),
  ('plumbing', 'plumbing.tee_20', 'VERO Тройник 20', 'plumbing', 'шт', 'plumbing/037.jpg'),
  ('plumbing', 'plumbing.tee_25', 'VERO Тройник 25', 'plumbing', 'шт', 'plumbing/038.jpg'),
  ('plumbing', 'plumbing.tee_female_20_half', 'VERO Тройник комб. с В/Р 20х1/2', 'plumbing', 'шт', 'plumbing/039.jpg'),
  ('plumbing', 'plumbing.tee_female_25_half', 'VERO Тройник комб. с В/Р 25х1/2', 'plumbing', 'шт', 'plumbing/040.jpg'),
  ('plumbing', 'plumbing.tee_male_20_half', 'VERO Тройник комб. с Н/Р 20х1/2', 'plumbing', 'шт', 'plumbing/041.jpg'),
  ('plumbing', 'plumbing.tee_male_25_half', 'VERO Тройник комб. с Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/042.jpg'),
  ('plumbing', 'plumbing.tee_reducing_25_20_25', 'VERO Тройник переходник 25-20-25', 'plumbing', 'шт', 'plumbing/043.jpg'),
  ('plumbing', 'plumbing.tee_reducing_32_20_32', 'VERO Тройник переходник 32-20-32', 'plumbing', 'шт', 'plumbing/044.jpg'),
  ('plumbing', 'plumbing.radiator_valve_angle_20', 'VERO Угловой кран для радиатора 20х1/2', 'plumbing', 'шт', 'plumbing/045.jpg'),
  ('plumbing', 'plumbing.radiator_valve_angle_20_import', 'VERO Угловой кран для радиатора 20х1/2 (импорт)', 'plumbing', 'шт', 'plumbing/046.jpg'),
  ('plumbing', 'plumbing.elbow_female_20_half', 'VERO Угол В/Р 20х1/2', 'plumbing', 'шт', 'plumbing/047.jpg'),
  ('plumbing', 'plumbing.elbow_female_25_half', 'VERO Угол В/Р 25х1/2', 'plumbing', 'шт', 'plumbing/048.jpg'),
  ('plumbing', 'plumbing.elbow_male_20_half', 'VERO Угол Н/Р 20х1/2', 'plumbing', 'шт', 'plumbing/049.jpg'),
  ('plumbing', 'plumbing.elbow_male_25_half', 'VERO Угол Н/Р 25х1/2', 'plumbing', 'шт', 'plumbing/050.jpg'),
  ('plumbing', 'plumbing.elbow_nipple_20_half', 'VERO Угол с накидной гайкой (ниппель) 20х1/2', 'plumbing', 'шт', 'plumbing/051.jpg'),
  ('plumbing', 'plumbing.elbow_nipple_25_three_quarter', 'VERO Угол с накидной гайкой (ниппель) 25х3/4', 'plumbing', 'шт', 'plumbing/052.jpg'),
  ('plumbing', 'plumbing.filter_20_brass', 'VERO Фильтр 20 «мама» (латунь)', 'plumbing', 'шт', 'plumbing/053.jpg'),
  ('plumbing', 'plumbing.filter_25_brass', 'VERO Фильтр 25 «мама» (латунь)', 'plumbing', 'шт', 'plumbing/054.jpg'),
  ('plumbing', 'plumbing.ball_valve_20', 'VERO Шаровой кран 20', 'plumbing', 'шт', 'plumbing/055.jpg'),
  ('plumbing', 'plumbing.ball_valve_25', 'VERO Шаровой кран 25', 'plumbing', 'шт', 'plumbing/056.jpg'),
  ('plumbing', 'plumbing.ball_valve_20_eco', 'VERO Шаровой кран 20 ECO', 'plumbing', 'шт', 'plumbing/057.jpg'),
  ('plumbing', 'plumbing.ball_valve_25_eco', 'VERO Шаровой кран 25 ECO', 'plumbing', 'шт', 'plumbing/058.jpg');

INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path) VALUES
  ('wood', 'wood.board_25x150', 'Доска обрезная 25х150х6000', 'lumber', 'шт', NULL),
  ('wood', 'wood.beam_100x100', 'Брус 100х100х6000', 'lumber', 'шт', NULL),
  ('wood', 'wood.beam_50x50', 'Брус 50х50х3000', 'lumber', 'шт', NULL),
  ('wood', 'wood.batten_20x40', 'Рейка монтажная 20х40', 'lumber', 'м', NULL),
  ('wood', 'wood.lining_conifer', 'Вагонка хвойная', 'lumber', 'м²', NULL),
  ('wood', 'wood.floorboard_36', 'Доска половая, 36 мм', 'lumber', 'м²', NULL),
  ('wood', 'wood.plywood_fk_10', 'Фанера ФК 10 мм, 1525х1525', 'lumber', 'лист', NULL),
  ('wood', 'wood.osb3_9', 'Плита ОСБ-3 9 мм, 1250х2500', 'lumber', 'лист', NULL),
  ('wood', 'wood.chipboard_16', 'ДСП ламинированная, 16 мм', 'lumber', 'лист', NULL),
  ('wood', 'wood.mdf_panel', 'МДФ панель 2600х200', 'lumber', 'шт', NULL);

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
