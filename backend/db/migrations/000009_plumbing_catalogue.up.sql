-- the plumbing catalogue gets the universal one's treatment from 000007: a name, a description line and a
-- section per row, so a shop's grid is split by the «Категории» sheet. 35 products are new; their photos
-- are uploaded from the panel afterwards, so they start without one.
--
-- keys stay, because they are what prices are compared by. the seven that named a 25 mm fitting
-- (`clip_25`, `tee_25` ...) are the 20 mm ones in the new list and are renamed with their products, so no
-- shop loses a price; their 32 mm counterparts are new rows.

CREATE TEMP TABLE plumbing_catalogue (
    position     INT PRIMARY KEY,
    old_key      TEXT,
    template_key TEXT NOT NULL,
    name         TEXT NOT NULL,
    specs        TEXT NOT NULL,
    section      TEXT NOT NULL
);

INSERT INTO plumbing_catalogue (position, old_key, template_key, name, specs, section) VALUES
    (1, NULL, 'plumbing.ppr_pipe_cold_20', 'Труба PPR для холодной воды', '20 мм · PN16 · ХВС · VERO', 'pipes_insulation'),
    (2, NULL, 'plumbing.ppr_pipe_cold_25', 'Труба PPR для холодной воды', '25 мм · PN16 · ХВС · VERO', 'pipes_insulation'),
    (3, NULL, 'plumbing.ppr_pipe_cold_32', 'Труба PPR для холодной воды', '32 мм · PN16 · ХВС · VERO', 'pipes_insulation'),
    (4, NULL, 'plumbing.ppr_pipe_cold_63', 'Труба PPR для холодной воды', '63 мм · PN16 · ХВС · VERO', 'pipes_insulation'),
    (5, NULL, 'plumbing.ppr_pipe_hot_20', 'Труба PPR для горячей воды', '20 мм · PN20 · ГВС · VERO', 'pipes_insulation'),
    (6, NULL, 'plumbing.ppr_pipe_hot_25', 'Труба PPR для горячей воды', '25 мм · PN20 · ГВС · VERO', 'pipes_insulation'),
    (7, NULL, 'plumbing.ppr_pipe_hot_32', 'Труба PPR для горячей воды', '32 мм · PN20 · ГВС · VERO', 'pipes_insulation'),
    (8, NULL, 'plumbing.ppr_pipe_hot_63', 'Труба PPR для горячей воды', '63 мм · PN20 · ГВС · VERO', 'pipes_insulation'),
    (9, NULL, 'plumbing.floor_pipe_pert_red', 'Труба для тёплого пола', 'PE-RT · Красная · VERO', 'pipes_insulation'),
    (10, NULL, 'plumbing.floor_pipe_pexal_16', 'Металлопластиковая труба для тёплого пола', '16 × 2,0 мм · PEX-B-AL-PEX · VERO', 'pipes_insulation'),
    (11, 'plumbing.thermoflex_28x6_red', 'plumbing.thermoflex_28x6_red', 'Термофлекс', '28 мм · 6 мм · 2 м · Красный', 'pipes_insulation'),
    (12, 'plumbing.thermoflex_28x6_blue', 'plumbing.thermoflex_28x6_blue', 'Термофлекс', '28 мм · 6 мм · 2 м · Синий', 'pipes_insulation'),
    (13, 'plumbing.clip_25', 'plumbing.clip_20', 'Клипса PPR', '20 мм · VERO', 'ppr_fittings'),
    (14, NULL, 'plumbing.clip_32', 'Клипса PPR', '32 мм · VERO', 'ppr_fittings'),
    (15, 'plumbing.cross_90_20', 'plumbing.cross_90_20', 'Крестовина PPR', '20 мм · 90° · VERO', 'ppr_fittings'),
    (16, NULL, 'plumbing.cross_90_32', 'Крестовина PPR', '32 мм · 90° · VERO', 'ppr_fittings'),
    (17, 'plumbing.clamp_metal_45_52', 'plumbing.clamp_metal_45_52', 'Хомут трубный', '45–52 мм · 1 1/2″ · Металлический · С резиновой вставкой · VERO', 'ppr_fittings'),
    (18, 'plumbing.coupling_25', 'plumbing.coupling_20', 'Муфта PPR', '20 мм · VERO', 'ppr_fittings'),
    (19, NULL, 'plumbing.coupling_32', 'Муфта PPR', '32 мм · VERO', 'ppr_fittings'),
    (20, 'plumbing.adapter_coupling_female_25', 'plumbing.adapter_coupling_female_25', 'Муфта комбинированная', '25 × 1/2″ · Внутренняя резьба · VERO', 'ppr_fittings'),
    (21, 'plumbing.adapter_coupling_male_25', 'plumbing.adapter_coupling_male_25', 'Муфта комбинированная', '25 × 1/2″ · Наружная резьба · VERO', 'ppr_fittings'),
    (22, 'plumbing.adapter_nipple_25_half', 'plumbing.adapter_nipple_25_half', 'Адаптер с накидной гайкой', '25 × 1/2″ · Ниппель · VERO', 'ppr_fittings'),
    (23, 'plumbing.reducer_32_20', 'plumbing.reducer_32_20', 'Переходник PPR', '32 × 20 мм · VERO', 'ppr_fittings'),
    (24, 'plumbing.bypass_25', 'plumbing.bypass_20', 'Обвод PPR', '20 мм · VERO', 'ppr_fittings'),
    (25, NULL, 'plumbing.bypass_32', 'Обвод PPR', '32 мм · VERO', 'ppr_fittings'),
    (26, 'plumbing.elbow_45_25', 'plumbing.elbow_45_20', 'Полуотвод PPR', '20 мм · VERO', 'ppr_fittings'),
    (27, NULL, 'plumbing.elbow_45_32', 'Полуотвод PPR', '32 мм · VERO', 'ppr_fittings'),
    (28, 'plumbing.elbow_90_25', 'plumbing.elbow_90_20', 'Отвод PPR', '20 мм · 90° · VERO', 'ppr_fittings'),
    (29, NULL, 'plumbing.elbow_90_32', 'Отвод PPR', '32 мм · 90° · VERO', 'ppr_fittings'),
    (30, 'plumbing.elbow_wall_female_20', 'plumbing.elbow_wall_female_20', 'Отвод настенный', '20 × 1/2″ · Внутренняя резьба · VERO', 'ppr_fittings'),
    (31, 'plumbing.elbow_wall_male_20', 'plumbing.elbow_wall_male_20', 'Отвод настенный', '20 × 1/2″ · Наружная резьба · VERO', 'ppr_fittings'),
    (32, 'plumbing.double_elbow_bracket_female_20', 'plumbing.double_elbow_bracket_female_20', 'Двойной отвод с креплением', '20 × 15 мм · Внутренняя резьба · VERO', 'ppr_fittings'),
    (33, 'plumbing.double_elbow_bracket_male_20', 'plumbing.double_elbow_bracket_male_20', 'Двойной отвод с креплением', '20 × 15 мм · Наружная резьба · VERO', 'ppr_fittings'),
    (34, 'plumbing.plug_25', 'plumbing.plug_20', 'Заглушка PPR', '20 мм · VERO', 'ppr_fittings'),
    (35, NULL, 'plumbing.plug_32', 'Заглушка PPR', '32 мм · VERO', 'ppr_fittings'),
    (36, 'plumbing.union_male_25_half', 'plumbing.union_male_25_half', 'Ракор', '25 × 1/2″ · Наружная резьба · VERO', 'ppr_fittings'),
    (37, 'plumbing.union_female_25_three_quarter', 'plumbing.union_female_25_three_quarter', 'Ракор', '25 × 3/4″ · Внутренняя резьба · VERO', 'ppr_fittings'),
    (38, 'plumbing.tee_25', 'plumbing.tee_20', 'Тройник PPR', '20 мм · VERO', 'ppr_fittings'),
    (39, NULL, 'plumbing.tee_32', 'Тройник PPR', '32 мм · VERO', 'ppr_fittings'),
    (40, 'plumbing.tee_female_20_half', 'plumbing.tee_female_20_half', 'Тройник комбинированный', '20 × 1/2″ · Внутренняя резьба · VERO', 'ppr_fittings'),
    (41, 'plumbing.tee_male_25_half', 'plumbing.tee_male_25_half', 'Тройник комбинированный', '25 × 1/2″ · Наружная резьба · VERO', 'ppr_fittings'),
    (42, 'plumbing.tee_reducing_32_20_32', 'plumbing.tee_reducing_32_20_32', 'Тройник переходной', '32 × 20 × 32 мм · VERO', 'ppr_fittings'),
    (43, 'plumbing.elbow_female_25_half', 'plumbing.elbow_female_25_half', 'Угол комбинированный', '25 × 1/2″ · Внутренняя резьба · VERO', 'ppr_fittings'),
    (44, 'plumbing.elbow_male_25_half', 'plumbing.elbow_male_25_half', 'Угол комбинированный', '25 × 1/2″ · Наружная резьба · VERO', 'ppr_fittings'),
    (45, 'plumbing.elbow_nipple_25_three_quarter', 'plumbing.elbow_nipple_25_three_quarter', 'Угол с накидной гайкой', '25 × 3/4″ · Ниппель · VERO', 'ppr_fittings'),
    (46, 'plumbing.filter_25_brass', 'plumbing.filter_25_brass', 'Фильтр комбинированный', '25 мм · Внутренняя резьба · Латунь · VERO', 'ppr_fittings'),
    (47, NULL, 'plumbing.butterfly_valve_20', 'Вентиль барашковый', '20 мм · VERO', 'valves_vero'),
    (48, NULL, 'plumbing.butterfly_valve_25', 'Вентиль барашковый', '25 мм · VERO', 'valves_vero'),
    (49, 'plumbing.ball_valve_20', 'plumbing.ball_valve_20', 'Шаровой кран', '20 мм · Красная ручка · VERO', 'valves_vero'),
    (50, 'plumbing.ball_valve_20_eco', 'plumbing.ball_valve_20_eco', 'Шаровой кран', '20 мм · ECO · Белая ручка · VERO', 'valves_vero'),
    (51, NULL, 'plumbing.ball_valve_32_eco', 'Шаровой кран', '32 мм · ECO · VERO', 'valves_vero'),
    (52, 'plumbing.radiator_valve_angle_20', 'plumbing.radiator_valve_angle_20', 'Угловой кран для радиатора', '20 × 1/2″ · VERO', 'valves_vero'),
    (53, 'plumbing.radiator_valve_angle_20_import', 'plumbing.radiator_valve_angle_20_import', 'Угловой кран для радиатора', '20 × 1/2″ · Импортный · VERO', 'valves_vero'),
    (54, 'plumbing.sewer_pipe_50_3m', 'plumbing.sewer_pipe_50_3m', 'Канализационная труба', 'Ø50 мм · 3 м · VERO', 'sewer'),
    (55, 'plumbing.sewer_pipe_75_3m', 'plumbing.sewer_pipe_75_3m', 'Канализационная труба', 'Ø75 мм · 3 м · VERO', 'sewer'),
    (56, 'plumbing.sewer_pipe_100_3m', 'plumbing.sewer_pipe_100_3m', 'Канализационная труба', 'Ø100 мм · 3 м · VERO', 'sewer'),
    (57, 'plumbing.sewer_pipe_150_3m', 'plumbing.sewer_pipe_150_3m', 'Канализационная труба', 'Ø150 мм · 3 м · VERO', 'sewer'),
    (58, 'plumbing.sewer_clip_50', 'plumbing.sewer_clip_50', 'Клипса для канализационной трубы', 'Ø50 мм · VERO', 'sewer'),
    (59, 'plumbing.sewer_clip_100', 'plumbing.sewer_clip_100', 'Клипса для канализационной трубы', 'Ø100 мм · VERO', 'sewer'),
    (60, 'plumbing.sewer_coupling_110', 'plumbing.sewer_coupling_110', 'Муфта канализационная', '110 мм · VERO', 'sewer'),
    (61, 'plumbing.sewer_elbow_45_100', 'plumbing.sewer_elbow_45_100', 'Полуотвод канализационный', '100 мм · 45° · VERO', 'sewer'),
    (62, 'plumbing.sewer_elbow_100', 'plumbing.sewer_elbow_100', 'Отвод канализационный', '100 мм · 90° · VERO', 'sewer'),
    (63, 'plumbing.sewer_tee_100_50', 'plumbing.sewer_tee_100_50', 'Тройник канализационный', '100 × 50 мм · 90° · VERO', 'sewer'),
    (64, 'plumbing.sewer_tee_100_100', 'plumbing.sewer_tee_100_100', 'Тройник канализационный', '100 × 100 мм · 90° · VERO', 'sewer'),
    (65, 'plumbing.barrel_nipple_15_cheap', 'plumbing.barrel_nipple_15_cheap', 'Ниппель резьбовой', '15 мм · Латунь · Эконом', 'threaded_fittings'),
    (66, 'plumbing.barrel_nipple_15_brass', 'plumbing.barrel_nipple_15_brass', 'Ниппель резьбовой', '15 мм · Латунь · С уплотнителем', 'threaded_fittings'),
    (67, 'plumbing.plug_20_male_cheap', 'plumbing.plug_20_male_cheap', 'Заглушка резьбовая', '20 мм · Внутренняя резьба · Латунь · Эконом', 'threaded_fittings'),
    (68, 'plumbing.calso_15x20_cheap', 'plumbing.calso_15x20_cheap', 'Футорка переходная', '15 × 20 мм · Внутренняя + наружная резьба · Латунь · Эконом', 'threaded_fittings'),
    (69, 'plumbing.calso_15x20_steel', 'plumbing.calso_15x20_steel', 'Футорка переходная', '15 × 20 мм · Внутренняя + наружная резьба · Нержавеющая сталь', 'threaded_fittings'),
    (70, 'plumbing.coupling_20_steel', 'plumbing.coupling_20_steel', 'Муфта резьбовая', '20 мм · 2 × внутренняя резьба · AISI 304', 'threaded_fittings'),
    (71, 'plumbing.elbow_15_brass', 'plumbing.elbow_15_brass', 'Отвод резьбовой', '15 мм · 2 × внутренняя резьба · Латунь', 'threaded_fittings'),
    (72, 'plumbing.elbow_15_steel', 'plumbing.elbow_15_steel', 'Отвод резьбовой', '15 мм · Внутренняя + наружная резьба · AISI 304', 'threaded_fittings'),
    (73, 'plumbing.reducer_20x25_steel', 'plumbing.reducer_20x25_steel', 'Ниппель переходной', '20 × 25 мм · 2 × наружная резьба · Нержавеющая сталь', 'threaded_fittings'),
    (74, 'plumbing.tee_15_mmm_brass', 'plumbing.tee_15_mmm_brass', 'Тройник резьбовой', '15 мм · 3 × внутренняя резьба · Латунь', 'threaded_fittings'),
    (75, 'plumbing.tee_15_mmf_brass', 'plumbing.tee_15_mmf_brass', 'Тройник резьбовой', '15 мм · 2 × внутренняя + 1 × наружная резьба · Латунь', 'threaded_fittings'),
    (76, 'plumbing.nipple_15_male_cheap', 'plumbing.nipple_15_male_cheap', 'Штуцер резьбовой', 'Наружная резьба · Латунь', 'threaded_fittings'),
    (77, 'plumbing.eccentric_brass_90', 'plumbing.eccentric_brass_90', 'Ниппель переходной', 'Латунь', 'threaded_fittings'),
    (78, 'plumbing.extension_15', 'plumbing.extension_15', 'Удлинитель резьбовой', '15 мм · Хромированный', 'threaded_fittings'),
    (79, 'plumbing.coupling_16', 'plumbing.coupling_16', 'Муфта обжимная', '16 мм · Латунь · KTM', 'ktm_fittings'),
    (80, 'plumbing.elbow_16_ktm', 'plumbing.elbow_16_ktm', 'Отвод обжимной', '16 мм · Латунь · KTM', 'ktm_fittings'),
    (81, 'plumbing.tee_16_ktm', 'plumbing.tee_16_ktm', 'Тройник обжимной', '16 мм · Латунь · KTM', 'ktm_fittings'),
    (82, NULL, 'plumbing.kas_gas_butterfly_20', 'Газовый вентиль «Бабочка»', '20 мм · Наружная + внутренняя резьба · NEW · KAS', 'valves_kas'),
    (83, NULL, 'plumbing.kas_butterfly_eco_20', 'Вентиль «Бабочка»', '20 мм · 2 × внутренняя резьба · ECO · KAS', 'valves_kas'),
    (84, NULL, 'plumbing.kas_ball_valve_water_20', 'Шаровой кран для воды', '20 мм · 2 × внутренняя резьба · Красная ручка · NEW · KAS', 'valves_kas'),
    (85, NULL, 'plumbing.kas_gas_ball_valve_34', 'Газовый шаровой кран', '3/4″ · 2 × внутренняя резьба', 'valves_kas'),
    (86, NULL, 'plumbing.kas_washer_valve_15x20', 'Кран для стиральной машины', '15 × 20 мм · Матовый · KAS', 'valves_kas'),
    (87, NULL, 'plumbing.kas_angle_valve_eco_12', 'Угловой кран', '1/2″ · ECO · NEW · KAS Italy', 'valves_kas'),
    (88, NULL, 'plumbing.kas_angle_valve_rubber_12', 'Угловой кран', '1/2″ · С резиновым сальником · KAS Italy', 'valves_kas'),
    (89, 'plumbing.cistern_valve_dual_flush', 'plumbing.cistern_valve_dual_flush', 'Сливной механизм для бачка', 'Нижний выпуск · Двухрежимный', 'cistern_toilet'),
    (90, 'plumbing.cistern_float_side', 'plumbing.cistern_float_side', 'Заливной клапан для бачка', 'Боковая подводка · Пластиковый', 'cistern_toilet'),
    (91, 'plumbing.toilet_corrugation', 'plumbing.toilet_corrugation', 'Гофра для унитаза', 'Прямая · Белая', 'cistern_toilet'),
    (92, 'plumbing.toilet_corrugation_angle', 'plumbing.toilet_corrugation_angle', 'Гофра для унитаза', 'Угловая · Белая', 'cistern_toilet'),
    (93, 'plumbing.toilet_seat_fixing', 'plumbing.toilet_seat_fixing', 'Крепление для сиденья унитаза', 'Комплект · Белое', 'cistern_toilet'),
    (94, 'plumbing.toilet_seat_cover', 'plumbing.toilet_seat_cover', 'Сиденье для унитаза', 'С крышкой · Белое', 'cistern_toilet'),
    (95, 'plumbing.siphon_rubber_seal', 'plumbing.siphon_rubber_seal', 'Вставка-антизапах для сифона', 'Синяя', 'siphons'),
    (96, 'plumbing.siphon_outlet_head', 'plumbing.siphon_outlet_head', 'Выпуск для сифона', 'Хромированная решётка', 'siphons'),
    (97, 'plumbing.siphon_bowl_round_overflow', 'plumbing.siphon_bowl_round_overflow', 'Сифон для мойки', 'С тазиком · Круглый перелив', 'siphons'),
    (98, 'plumbing.siphon_sink_eco', 'plumbing.siphon_sink_eco', 'Сифон для мойки', 'С выпуском и переливом', 'siphons'),
    (99, 'plumbing.siphon_bath', 'plumbing.siphon_bath', 'Сифон для ванны', 'С переливом · Гибкий', 'siphons'),
    (100, 'plumbing.drain_shower_side_plastic', 'plumbing.drain_shower_side_plastic', 'Трап сливной для душа', 'Боковой выпуск · Пластиковый', 'drains'),
    (101, 'plumbing.drain_shower_straight_plastic', 'plumbing.drain_shower_straight_plastic', 'Трап сливной для душа', 'Прямой выпуск · Пластиковый', 'drains'),
    (102, 'plumbing.drain_aqua_ss28', 'plumbing.drain_aqua_ss28', 'Трап сливной', '10 × 10 см · SS-28 · AQUA', 'drains'),
    (103, 'plumbing.drain_aqua_12pro', 'plumbing.drain_aqua_12pro', 'Трап сливной', '10 × 10 см · 12 PRO · Никель · AQUA', 'drains'),
    (104, 'plumbing.drain_aqua_tile', 'plumbing.drain_aqua_tile', 'Трап под плитку', '10 × 10 см · Никель · AQUA', 'drains'),
    (105, 'plumbing.washer_drain_hose_190', 'plumbing.washer_drain_hose_190', 'Сливной шланг для стиральной машины', '1,9 м · Серый', 'washing_machine'),
    (106, 'plumbing.washer_drain_hose_290', 'plumbing.washer_drain_hose_290', 'Сливной шланг для стиральной машины', '2,9 м · Серый', 'washing_machine'),
    (107, 'plumbing.anti_vibration_pads', 'plumbing.anti_vibration_pads', 'Антивибрационные подставки', '4 шт · Для стиральной машины', 'washing_machine'),
    (108, 'plumbing.washer_inlet_hose_25', 'plumbing.washer_inlet_hose_25', 'Наливной шланг для стиральной машины', '2,5 м · Серый', 'washing_machine'),
    (109, NULL, 'plumbing.water_filter_1stage_boou', 'Фильтр для воды', '1-ступенчатый · 20 мм × 3/4″ · BOOU', 'filters_cartridges'),
    (110, NULL, 'plumbing.water_filter_3stage_boou', 'Фильтр для воды', '3-ступенчатый · 20 мм × 3/4″ · BOOU', 'filters_cartridges'),
    (111, NULL, 'plumbing.cartridge_set_3in1', 'Набор картриджей для фильтра', '3 в 1 · CTO + UDF + PP', 'filters_cartridges'),
    (112, NULL, 'plumbing.cartridge_thread', 'Картридж для фильтра', 'Нитяной', 'filters_cartridges'),
    (113, NULL, 'plumbing.cartridge_cotton', 'Картридж для фильтра', 'Хлопковый', 'filters_cartridges'),
    (114, 'plumbing.mixer_cartridge', 'plumbing.mixer_cartridge', 'Картридж для смесителя', 'Керамический', 'mixer_parts'),
    (115, 'plumbing.tap_valve_square_brass', 'plumbing.tap_valve_square_brass', 'Кран-букса', 'Квадратный шток · Латунь · Красная маркировка', 'mixer_parts'),
    (116, 'plumbing.tap_handle_cross_new', 'plumbing.tap_handle_cross_new', 'Ручка для смесителя', 'Крестовая · Хромированная · NEW', 'mixer_parts'),
    (117, 'plumbing.mixer_bracket', 'plumbing.mixer_bracket', 'Ручка смесителя', 'Рычажная · Хромированная', 'mixer_parts'),
    (118, NULL, 'plumbing.shutoff_valve_boou', 'Клапан-отсекатель', 'NEW · BOOU', 'mixer_parts'),
    (119, 'plumbing.boou_fixator_zl115', 'plumbing.boou_fixator_zl115', 'Фиксатор для смесителя', 'ZL-115 · BOOU', 'mixer_parts'),
    (120, 'plumbing.spout_filter_male', 'plumbing.spout_filter_male', 'Аэратор для гусака', 'С сальником · Наружная резьба', 'mixer_parts'),
    (121, 'plumbing.mixer_mic_aqua_19808', 'plumbing.mixer_mic_aqua_19808', 'Гусак для смесителя', 'Гибкий · Серый · 19808-27 · AQUA', 'mixer_parts'),
    (122, 'plumbing.mixer_mic_cheap', 'plumbing.mixer_mic_cheap', 'Излив для смесителя', 'Жёсткий · Хромированный', 'mixer_parts'),
    (123, NULL, 'plumbing.shower_holder_wall', 'Держатель для душевой лейки', 'Настенный · Хромированный', 'mixer_parts'),
    (124, 'plumbing.shower_head_aqua_r50', 'plumbing.shower_head_aqua_r50', 'Лейка душевая', 'AQ-R50 · AQUA', 'mixer_parts'),
    (125, 'plumbing.hose_reinforced_ms_alfa_70', 'plumbing.hose_reinforced_ms_alfa_70', 'Шланг армированный', '70 см · Внутренняя резьба + штуцер · ALFA', 'hoses'),
    (126, 'plumbing.hose_reinforced_mm_alfa_80', 'plumbing.hose_reinforced_mm_alfa_80', 'Шланг армированный', '80 см · 2 × внутренняя резьба · ALFA', 'hoses'),
    (127, 'plumbing.hose_mixer_boou_80', 'plumbing.hose_mixer_boou_80', 'Шланг для смесителя', '80 см · Штуцер «ёлка» · BOOU', 'hoses'),
    (128, 'plumbing.hose_water_boou_100', 'plumbing.hose_water_boou_100', 'Шланг для воды', '100 см · 2 × внутренняя резьба · BOOU', 'hoses'),
    (129, 'plumbing.shower_hose_aqua_aq01', 'plumbing.shower_hose_aqua_aq01', 'Шланг для душа', '1,5–1,8 м · AQ-01 · AQUA', 'hoses'),
    (130, 'plumbing.boou_mixer_shower_b8156_5s', 'plumbing.boou_mixer_shower_b8156_5s', 'Смеситель для душа', 'B8156-5S · BOOU', 'mixers'),
    (131, 'plumbing.boou_mixer_riser_7195', 'plumbing.boou_mixer_riser_7195', 'Смеситель для душевой стойки', '7195-75 · BOOU', 'mixers'),
    (132, 'plumbing.boou_mixer_mic_bz9184j', 'plumbing.boou_mixer_mic_bz9184j', 'Смеситель с гибким изливом', 'BZ9184J-E367 · BOOU', 'mixers'),
    (133, 'plumbing.boou_mixer_b8156_14a', 'plumbing.boou_mixer_b8156_14a', 'Смеситель', 'B8156-14A · BOOU', 'mixers'),
    (134, 'plumbing.mixer_electric_alfa', 'plumbing.mixer_electric_alfa', 'Электрический смеситель', 'Проточный · ALFA', 'mixers'),
    (135, 'plumbing.boou_mixer_bidet_b8246', 'plumbing.boou_mixer_bidet_b8246', 'Смеситель для тахарата', 'B8246-4AH-F805 · BOOU', 'mixers');

UPDATE products p
SET template_key = c.template_key
FROM plumbing_catalogue c
WHERE p.template_key = c.old_key
  AND c.old_key <> c.template_key;

-- rebuilt rather than updated: a shop's grid follows the template's row order (`ListProductsByShop`), and
-- the new list is grouped by section with the new rows between their siblings
CREATE TEMP TABLE plumbing_previous AS
SELECT * FROM product_templates WHERE shop_category = 'plumbing';

DELETE FROM product_templates WHERE shop_category = 'plumbing';

-- a new row starts outside the basket, so no live market drops out of the comparison
INSERT INTO product_templates (shop_category, template_key, name, category, unit, image_path,
                               in_basket, specs, section, created_at)
SELECT 'plumbing', c.template_key, c.name,
       COALESCE(o.category, 'plumbing'), COALESCE(o.unit, 'шт'), o.image_path,
       COALESCE(o.in_basket, FALSE), c.specs, c.section,
       COALESCE(o.created_at, CURRENT_TIMESTAMP)
FROM plumbing_catalogue c
LEFT JOIN plumbing_previous o ON o.template_key = c.old_key
ORDER BY c.position;

-- and into every plumbing shop already seeded, the way the sync button would: names, then the missing rows
UPDATE products p
SET name = t.name, specs = t.specs, section = t.section, updated_at = CURRENT_TIMESTAMP
FROM product_templates t
WHERE p.template_key = t.template_key
  AND t.shop_category = 'plumbing';

INSERT INTO products (shop_id, name, category, unit, template_key, image_path, in_basket, specs, section)
SELECT s.id, t.name, t.category, t.unit, t.template_key, t.image_path, t.in_basket, t.specs, t.section
FROM shops s
CROSS JOIN product_templates t
WHERE s.category = 'plumbing'
  AND t.shop_category = 'plumbing'
ON CONFLICT (shop_id, template_key) DO NOTHING;

DROP TABLE plumbing_previous;
DROP TABLE plumbing_catalogue;
