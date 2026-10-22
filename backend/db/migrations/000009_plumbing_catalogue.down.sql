-- back to the hundred old rows, their old names and no sections. photos and basket membership are
-- carried over from whatever the rows hold now; the 35 added products go, with any price typed on them.

CREATE TEMP TABLE plumbing_old (
    position     INT PRIMARY KEY,
    template_key TEXT NOT NULL,
    name         TEXT NOT NULL
);

INSERT INTO plumbing_old (position, template_key, name) VALUES
    (1, 'plumbing.adapter_coupling_female_25', 'VERO Адаптер-муфта комб. В/Р 25х1/2'),
    (2, 'plumbing.adapter_coupling_male_25', 'VERO Адаптер-муфта комб. Н/Р 25х1/2'),
    (3, 'plumbing.adapter_nipple_25_half', 'VERO Адаптер с накидной гайкой (ниппель) 25х1/2'),
    (4, 'plumbing.double_elbow_bracket_female_20', 'VERO Двойной отвод с креплением В/Р 20х15'),
    (5, 'plumbing.double_elbow_bracket_male_20', 'VERO Двойной отвод с креплением Н/Р 20х15'),
    (6, 'plumbing.plug_25', 'VERO Заглушка 25'),
    (7, 'plumbing.clip_25', 'VERO Клипса 25'),
    (8, 'plumbing.cross_90_20', 'VERO Крестовина 90° 20'),
    (9, 'plumbing.clamp_metal_45_52', 'VERO Хомут металлический 45-52 (1 1/2")'),
    (10, 'plumbing.coupling_25', 'VERO Муфта 25'),
    (11, 'plumbing.bypass_25', 'VERO Обвод 25'),
    (12, 'plumbing.elbow_90_25', 'VERO Отвод 90° 25'),
    (13, 'plumbing.elbow_wall_female_20', 'VERO Отвод с настенным креплением В/Р 20'),
    (14, 'plumbing.elbow_wall_male_20', 'VERO Отвод с настенным креплением Н/Р 20'),
    (15, 'plumbing.reducer_32_20', 'VERO Переходник 32-20'),
    (16, 'plumbing.elbow_45_25', 'VERO Полуотвод 25'),
    (17, 'plumbing.union_female_25_three_quarter', 'VERO Ракор В/Р 25х3/4'),
    (18, 'plumbing.union_male_25_half', 'VERO Ракор Н/Р 25х1/2'),
    (19, 'plumbing.tee_25', 'VERO Тройник 25'),
    (20, 'plumbing.tee_female_20_half', 'VERO Тройник комб. с В/Р 20х1/2'),
    (21, 'plumbing.tee_male_25_half', 'VERO Тройник комб. с Н/Р 25х1/2'),
    (22, 'plumbing.tee_reducing_32_20_32', 'VERO Тройник переходник 32-20-32'),
    (23, 'plumbing.radiator_valve_angle_20', 'VERO Угловой кран для радиатора 20х1/2'),
    (24, 'plumbing.radiator_valve_angle_20_import', 'VERO Угловой кран для радиатора 20х1/2 (импорт)'),
    (25, 'plumbing.elbow_female_25_half', 'VERO Угол В/Р 25х1/2'),
    (26, 'plumbing.elbow_male_25_half', 'VERO Угол Н/Р 25х1/2'),
    (27, 'plumbing.elbow_nipple_25_three_quarter', 'VERO Угол с накидной гайкой (ниппель) 25х3/4'),
    (28, 'plumbing.filter_25_brass', 'VERO Фильтр 25 «мама» (латунь)'),
    (29, 'plumbing.ball_valve_20', 'VERO Шаровой кран 20'),
    (30, 'plumbing.ball_valve_20_eco', 'VERO Шаровой кран 20 ECO'),
    (31, 'plumbing.cistern_valve_dual_flush', 'Механизм нижний с двухрежимным выпуском'),
    (32, 'plumbing.cistern_float_side', 'Поплавок боковой (пластмасса)'),
    (33, 'plumbing.toilet_corrugation', 'Гофра для унитаза'),
    (34, 'plumbing.toilet_corrugation_angle', 'Гофра для унитаза угловая'),
    (35, 'plumbing.toilet_seat_fixing', 'Крепление для сиденья унитаза'),
    (36, 'plumbing.siphon_rubber_seal', 'Резина для сифона («вонючка»)'),
    (37, 'plumbing.siphon_outlet_head', 'Выпуск для сифона (головка)'),
    (38, 'plumbing.siphon_bowl_round_overflow', 'Сифон с тазиком и круглым переливом'),
    (39, 'plumbing.toilet_seat_cover', 'Сиденье с крышкой для унитаза'),
    (40, 'plumbing.siphon_bath', 'Сифон для ванны'),
    (41, 'plumbing.siphon_sink_eco', 'Сифон для мойки с выпуском и переливом ЭКО'),
    (42, 'plumbing.drain_shower_side_plastic', 'Трап сливной для душа, боковой (пластик)'),
    (43, 'plumbing.drain_shower_straight_plastic', 'Трап сливной для душа, прямой (пластик)'),
    (44, 'plumbing.drain_aqua_ss28', 'Трап AQUA 10х10 SS-28'),
    (45, 'plumbing.drain_aqua_12pro', 'Трап 12 PRO AQUA 10х10 (никель)'),
    (46, 'plumbing.drain_aqua_tile', 'Трап под кафель AQUA 10х10 (никель)'),
    (47, 'plumbing.washer_drain_hose_190', 'Сливной шланг для стиральной машины 190 мм'),
    (48, 'plumbing.washer_drain_hose_290', 'Сливной шланг для стиральной машины 290 мм'),
    (49, 'plumbing.anti_vibration_pads', 'Антивибрационные подставки'),
    (50, 'plumbing.washer_inlet_hose_25', 'Шланг наливной 2,5 м'),
    (51, 'plumbing.mixer_cartridge', 'Механизм для джойстика'),
    (52, 'plumbing.tap_valve_square_brass', 'Кран-букса квадрат (латунь), красная'),
    (53, 'plumbing.tap_handle_cross_new', 'Барашек крестовой NEW'),
    (54, 'plumbing.mixer_bracket', 'Лапка смесителя'),
    (55, 'plumbing.boou_fixator_zl115', 'BOOU Фиксатор ZL-115'),
    (56, 'plumbing.spout_filter_male', 'Фильтр для гусака с сальником (н/р)'),
    (57, 'plumbing.mixer_mic_aqua_19808', 'Смеситель-микрофон гусак серый AQUA 19808-27'),
    (58, 'plumbing.mixer_mic_cheap', 'Смеситель-микрофон гусак (дешёвый)'),
    (59, 'plumbing.shower_hose_aqua_aq01', 'Душевой шланг AQUA 1,5-1,8 м AQ-01'),
    (60, 'plumbing.hose_reinforced_mm_alfa_80', 'Шланг армированный м/м ALFA 80 см'),
    (61, 'plumbing.hose_reinforced_ms_alfa_70', 'Шланг армированный м/с ALFA 70 см'),
    (62, 'plumbing.hose_water_boou_100', 'Шланг для воды BOOU м/м 100 см'),
    (63, 'plumbing.hose_mixer_boou_80', 'Шланг для смесителя BOOU «ёлка» 80 см'),
    (64, 'plumbing.shower_head_aqua_r50', 'Лейка AQUA AQ-R50'),
    (65, 'plumbing.thermoflex_28x6_red', 'Термофлекс 28х6/2 красный'),
    (66, 'plumbing.thermoflex_28x6_blue', 'Термофлекс 28х6/2 синий'),
    (67, 'plumbing.sewer_pipe_100_3m', 'VERO Канализационная труба 2,2 мм — 100/3 м'),
    (68, 'plumbing.sewer_pipe_50_3m', 'VERO Канализационная труба 2,2 мм — 50/3 м'),
    (69, 'plumbing.sewer_pipe_75_3m', 'VERO Канализационная труба 2,2 мм — 75/3 м'),
    (70, 'plumbing.sewer_pipe_150_3m', 'VERO Канализационная труба 3,2 мм — 150/3 м'),
    (71, 'plumbing.sewer_clip_100', 'VERO (к) Клипса 100'),
    (72, 'plumbing.sewer_clip_50', 'VERO (к) Клипса 50'),
    (73, 'plumbing.sewer_coupling_110', 'VERO (к) Муфта 110'),
    (74, 'plumbing.sewer_elbow_100', 'VERO (к) Отвод 100'),
    (75, 'plumbing.sewer_elbow_45_100', 'VERO (к) Полуотвод 100'),
    (76, 'plumbing.sewer_tee_100_100', 'VERO (к) Тройник 100/100 90°'),
    (77, 'plumbing.sewer_tee_100_50', 'VERO (к) Тройник 100/50 90°'),
    (78, 'plumbing.barrel_nipple_15_cheap', 'Бочонок (дешёвый) 15'),
    (79, 'plumbing.barrel_nipple_15_brass', 'Бочонок латунный (сальник) 15'),
    (80, 'plumbing.plug_20_male_cheap', 'Заглушка 20 М (дешёвая)'),
    (81, 'plumbing.calso_15x20_cheap', 'Кальсо (дешёвое) 15х20 М-П'),
    (82, 'plumbing.calso_15x20_steel', 'Кальсо нержавейка 15х20 М-П'),
    (83, 'plumbing.coupling_20_steel', 'Муфта нержавейка 20 (304)'),
    (84, 'plumbing.elbow_15_brass', 'Отвод 15 М-М (латунный)'),
    (85, 'plumbing.elbow_15_steel', 'Отвод нержавейка 15 (304) М-П'),
    (86, 'plumbing.reducer_20x25_steel', 'Переходник нержавейка 20х25 П-П'),
    (87, 'plumbing.tee_15_mmm_brass', 'Тройник 15 М-М-М (латунный)'),
    (88, 'plumbing.tee_15_mmf_brass', 'Тройник 15 М-М-П (латунный)'),
    (89, 'plumbing.nipple_15_male_cheap', 'Штуцер 15 н/р (дешёвый)'),
    (90, 'plumbing.eccentric_brass_90', 'Эксцентрик (латунный) 90'),
    (91, 'plumbing.extension_15', 'Удлинитель 1,5 см'),
    (92, 'plumbing.coupling_16', 'Муфта 16'),
    (93, 'plumbing.elbow_16_ktm', 'Отвод (латунный) 16 КТМ'),
    (94, 'plumbing.tee_16_ktm', 'Тройник 16 КТМ'),
    (95, 'plumbing.boou_mixer_shower_b8156_5s', 'BOOU Смеситель для душа B8156-5S (Ж)'),
    (96, 'plumbing.boou_mixer_riser_7195', 'BOOU Смеситель стояк 7195-75 (Ж)'),
    (97, 'plumbing.boou_mixer_mic_bz9184j', 'BOOU Смеситель-микрофон BZ9184J-E367 (Ж)'),
    (98, 'plumbing.boou_mixer_b8156_14a', 'BOOU Смеситель B8156-14A (Ж)'),
    (99, 'plumbing.mixer_electric_alfa', 'Электрический смеситель ALFA'),
    (100, 'plumbing.boou_mixer_bidet_b8246', 'BOOU Смеситель «тахорат» B8246-4AH-F805 (Ж)');

CREATE TEMP TABLE plumbing_rekeyed (old_key TEXT PRIMARY KEY, new_key TEXT NOT NULL);

INSERT INTO plumbing_rekeyed (old_key, new_key) VALUES
    ('plumbing.clip_25', 'plumbing.clip_20'),
    ('plumbing.coupling_25', 'plumbing.coupling_20'),
    ('plumbing.bypass_25', 'plumbing.bypass_20'),
    ('plumbing.elbow_45_25', 'plumbing.elbow_45_20'),
    ('plumbing.elbow_90_25', 'plumbing.elbow_90_20'),
    ('plumbing.plug_25', 'plumbing.plug_20'),
    ('plumbing.tee_25', 'plumbing.tee_20');

UPDATE products p
SET template_key = r.old_key
FROM plumbing_rekeyed r
WHERE p.template_key = r.new_key;

UPDATE product_templates t
SET template_key = r.old_key
FROM plumbing_rekeyed r
WHERE t.template_key = r.new_key;

DELETE FROM products p
USING shops s
WHERE p.shop_id = s.id
  AND s.category = 'plumbing'
  AND p.template_key IS NOT NULL
  AND p.template_key NOT IN (SELECT template_key FROM plumbing_old);

CREATE TEMP TABLE plumbing_previous AS
SELECT * FROM product_templates WHERE shop_category = 'plumbing';

DELETE FROM product_templates WHERE shop_category = 'plumbing';

INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path,
                               in_basket, specs, section, created_at)
SELECT 'plumbing', o.template_key, o.name, c.category, c.unit, c.image_path,
       c.in_basket, '', '', c.created_at
FROM plumbing_old o
JOIN plumbing_previous c ON c.template_key = o.template_key
ORDER BY o.position;

UPDATE products p
SET name = o.name, specs = '', section = '', updated_at = CURRENT_TIMESTAMP
FROM plumbing_old o
WHERE p.template_key = o.template_key;

DROP TABLE plumbing_previous;
DROP TABLE plumbing_rekeyed;
DROP TABLE plumbing_old;
