-- Демонстрационные данные для показа инвесторам.
--
-- Пятьдесят магазинов по районам Ташкента, у каждого свой владелец и полностью проставленный
-- прайс, плюс тридцать обычных пользователей. Цены реальные для Ташкента; у каждого магазина
-- свой множитель, поэтому индекс корзины расходится по рынку и значки «дешевле/дороже рынка»
-- показывают настоящий разброс, а не одинаковые числа.
--
-- **Идентификаторы 900001+ зарезервированы за демо-данными.** Последовательности их не выдают,
-- поэтому настоящие регистрации продолжают получать обычные id, а всё демо удаляется одной
-- строкой - первым же оператором ниже. Повторный запуск скрипта безопасен.
--
--     psql "$DB_URL" -f backend/db/seed_demo.sql
--
-- Удалить всё, ничего не сеяв:
--
--     psql "$DB_URL" -c "DELETE FROM users WHERE id BETWEEN 900001 AND 900999"
--
-- Цены каталожных товаров четырёх магазинов основателя (112, 114, 115, 116) тоже проставляются -
-- без этого его собственные магазины единственные в базе стоят без индекса.

BEGIN;

-- предыдущий прогон: магазины и товары уходят каскадом за владельцами
DELETE FROM users WHERE id BETWEEN 900001 AND 900999;

-- ---------------------------------------------------------------- владельцы
INSERT INTO users (id, name, phone, role) VALUES
  (900001, 'Икром Эргашев', '998915839799', 'shop_owner'),
  (900002, 'Фаррух Алимов', '998990279487', 'shop_owner'),
  (900003, 'Шухрат Шарипов', '998919109934', 'shop_owner'),
  (900004, 'Азиз Юсупов', '998976658763', 'shop_owner'),
  (900005, 'Тимур Валиев', '998953592116', 'shop_owner'),
  (900006, 'Хасан Алимов', '998908120587', 'shop_owner'),
  (900007, 'Дилноза Исмоилова', '998914524011', 'shop_owner'),
  (900008, 'Шерзод Шарипов', '998999562152', 'shop_owner'),
  (900009, 'Икром Кодиров', '998900391618', 'shop_owner'),
  (900010, 'Рустам Тошматов', '998958734551', 'shop_owner'),
  (900011, 'Хасан Тошматов', '998911899957', 'shop_owner'),
  (900012, 'Шухрат Мирзаев', '998904570725', 'shop_owner'),
  (900013, 'Азиз Назаров', '998946322599', 'shop_owner'),
  (900014, 'Нодира Ходжаева', '998888950622', 'shop_owner'),
  (900015, 'Умид Алимов', '998945447143', 'shop_owner'),
  (900016, 'Гулнора Хакимова', '998949272755', 'shop_owner'),
  (900017, 'Мансур Мирзаев', '998934157903', 'shop_owner'),
  (900018, 'Шахло Шарипова', '998989485959', 'shop_owner'),
  (900019, 'Хасан Умаров', '998332648126', 'shop_owner'),
  (900020, 'Бахтиёр Ходжаев', '998991564121', 'shop_owner'),
  (900021, 'Камола Кодирова', '998884433943', 'shop_owner'),
  (900022, 'Фаррух Назаров', '998952721801', 'shop_owner'),
  (900023, 'Бахтиёр Каримов', '998950674659', 'shop_owner'),
  (900024, 'Акмаль Турсунов', '998917221424', 'shop_owner'),
  (900025, 'Улугбек Мусаев', '998977359225', 'shop_owner'),
  (900026, 'Мирзо Жураев', '998953849933', 'shop_owner'),
  (900027, 'Азамат Валиев', '998973007621', 'shop_owner'),
  (900028, 'Камол Исмоилов', '998930687891', 'shop_owner'),
  (900029, 'Сардор Каримов', '998888477797', 'shop_owner'),
  (900030, 'Бобур Расулов', '998959423201', 'shop_owner'),
  (900031, 'Ситора Жураева', '998974695056', 'shop_owner'),
  (900032, 'Нуриддин Каримов', '998939808905', 'shop_owner'),
  (900033, 'Азиз Каримов', '998987022777', 'shop_owner'),
  (900034, 'Зафар Ибрагимов', '998932554380', 'shop_owner'),
  (900035, 'Санжар Рахимов', '998975151318', 'shop_owner'),
  (900036, 'Лола Махмудова', '998884879734', 'shop_owner'),
  (900037, 'Жахонгир Собиров', '998932320612', 'shop_owner'),
  (900038, 'Икром Абдуллаев', '998938235809', 'shop_owner'),
  (900039, 'Зафар Тошматов', '998914587371', 'shop_owner'),
  (900040, 'Элёр Рахимов', '998918143680', 'shop_owner'),
  (900041, 'Азиза Бекмуродова', '998883806307', 'shop_owner'),
  (900042, 'Алишер Хакимов', '998913729949', 'shop_owner'),
  (900043, 'Азамат Ходжаев', '998991285429', 'shop_owner'),
  (900044, 'Рустам Исмоилов', '998944903422', 'shop_owner'),
  (900045, 'Мирзо Ярматов', '998937725266', 'shop_owner'),
  (900046, 'Камол Валиев', '998974812953', 'shop_owner'),
  (900047, 'Зафар Рахимов', '998905867443', 'shop_owner'),
  (900048, 'Санжар Ибрагимов', '998951991513', 'shop_owner'),
  (900049, 'Бобур Махмудов', '998949300939', 'shop_owner'),
  (900050, 'Нигора Кодирова', '998974511155', 'shop_owner');

-- ---------------------------------------------------------------- покупатели
INSERT INTO users (id, name, phone, role) VALUES
  (900051, 'Нилуфар Бекмуродова', '998989442964', 'customer'),
  (900052, 'Улугбек Алимов', '998334207464', 'customer'),
  (900053, 'Акмаль Расулов', '998338464477', 'customer'),
  (900054, 'Акмаль Ганиев', '998951849378', 'customer'),
  (900055, 'Хуршид Эргашев', '998942133950', 'customer'),
  (900056, 'Хасан Рахимов', '998910773548', 'customer'),
  (900057, 'Малика Сафарова', '998910800865', 'customer'),
  (900058, 'Мансур Тошматов', '998987916781', 'customer'),
  (900059, 'Улугбек Нурматов', '998999622677', 'customer'),
  (900060, 'Нодир Мирзаев', '998989702819', 'customer'),
  (900061, 'Санобар Валиева', '998909014210', 'customer'),
  (900062, 'Севара Ганиева', '998952834004', 'customer'),
  (900063, 'Шерзод Нурматов', '998336151365', 'customer'),
  (900064, 'Зарина Алимова', '998947447600', 'customer'),
  (900065, 'Бобур Юсупов', '998972488529', 'customer'),
  (900066, 'Ирода Нурматова', '998994524914', 'customer'),
  (900067, 'Лола Мирзаева', '998901130620', 'customer'),
  (900068, 'Ислом Аминов', '998907891230', 'customer'),
  (900069, 'Хусан Салимов', '998907579332', 'customer'),
  (900070, 'Мадина Кодирова', '998889609409', 'customer'),
  (900071, 'Мурод Шарипов', '998996794507', 'customer'),
  (900072, 'Дилшод Собиров', '998332245488', 'customer'),
  (900073, 'Жахонгир Собиров', '998958475256', 'customer'),
  (900074, 'Дилфуза Хакимова', '998332992389', 'customer'),
  (900075, 'Жахонгир Назаров', '998338084652', 'customer'),
  (900076, 'Умид Расулов', '998887709939', 'customer'),
  (900077, 'Достон Хакимов', '998988198052', 'customer'),
  (900078, 'Рустам Абдуллаев', '998916525862', 'customer'),
  (900079, 'Мохира Ганиева', '998944190679', 'customer'),
  (900080, 'Жасур Тошматов', '998959217069', 'customer');

-- ---------------------------------------------------------------- магазины
-- пять из них с оплаченным VIP-размещением: ровно столько слотов на главном экране.
INSERT INTO shops (id, user_id, name, address, contact_phone, category, location, vip_until) VALUES
  (900001, 900001, 'Qurilish Baza', 'Бунёдкор шоҳ кўчаси, 32, Чиланзар район, Ташкент', '998936487668', 'universal', ST_SetSRID(ST_MakePoint(69.205871, 41.275624), 4326), NULL),
  (900002, 900002, 'Стройдвор', 'Амира Темура кўчаси, 47, Юнусабад район, Ташкент', '998905746907', 'universal', ST_SetSRID(ST_MakePoint(69.301013, 41.353939), 4326), NULL),
  (900003, 900003, 'Мастер Дом', 'Мустақиллик шоҳ кўчаси, 72, Мирзо-Улугбек район, Ташкент', '998911531272', 'universal', ST_SetSRID(ST_MakePoint(69.347677, 41.332608), 4326), NULL),
  (900004, 900004, 'Bunyodkor Savdo', 'Фидокор кўчаси, 61, Яшнабад район, Ташкент', '998982412901', 'universal', ST_SetSRID(ST_MakePoint(69.308808, 41.286424), 4326), CURRENT_TIMESTAMP + INTERVAL '30 days'),
  (900005, 900005, 'Строймир', 'Сергели 7-квартал, 8, Сергели район, Ташкент', '998884678716', 'universal', ST_SetSRID(ST_MakePoint(69.206820, 41.224452), 4326), NULL),
  (900006, 900006, 'Qurilish Market', 'Зарқайнар кўчаси, 94, Шайхантахур район, Ташкент', '998902311218', 'universal', ST_SetSRID(ST_MakePoint(69.243728, 41.315914), 4326), NULL),
  (900007, 900007, 'Дом Строй', 'Уста Ширин кўчаси, 62, Алмазар район, Ташкент', '998334073363', 'universal', ST_SetSRID(ST_MakePoint(69.218321, 41.351245), 4326), NULL),
  (900008, 900008, 'Бинокор', 'Шота Руставели кўчаси, 35, Мирабад район, Ташкент', '998946115769', 'universal', ST_SetSRID(ST_MakePoint(69.273075, 41.298702), 4326), NULL),
  (900009, 900009, 'Usta Savdo', 'Чўпон Ота кўчаси, 88, Учтепа район, Ташкент', '998978265940', 'universal', ST_SetSRID(ST_MakePoint(69.194276, 41.298877), 4326), NULL),
  (900010, 900010, 'Строй Центр', 'Бобур кўчаси, 13, Яккасарай район, Ташкент', '998992345675', 'universal', ST_SetSRID(ST_MakePoint(69.242358, 41.295520), 4326), NULL),
  (900011, 900011, 'Темир Савдо', 'Бектемир кўчаси, 4, Бектемир район, Ташкент', '998337317774', 'universal', ST_SetSRID(ST_MakePoint(69.324421, 41.218963), 4326), NULL),
  (900012, 900012, 'Хона Курилиш', 'Бунёдкор шоҳ кўчаси, 72, Чиланзар район, Ташкент', '998953715018', 'universal', ST_SetSRID(ST_MakePoint(69.190892, 41.266464), 4326), CURRENT_TIMESTAMP + INTERVAL '30 days'),
  (900013, 900013, 'Строитель', 'Мингбулоқ кўчаси, 66, Юнусабад район, Ташкент', '998887063118', 'universal', ST_SetSRID(ST_MakePoint(69.298189, 41.365421), 4326), NULL),
  (900014, 900014, 'Baraka Qurilish', 'Ҳумо кўчаси, 40, Мирзо-Улугбек район, Ташкент', '998333193139', 'universal', ST_SetSRID(ST_MakePoint(69.344527, 41.338046), 4326), NULL),
  (900015, 900015, 'Ремонт Маркет', 'Авиасозлар кўчаси, 31, Яшнабад район, Ташкент', '998971840771', 'universal', ST_SetSRID(ST_MakePoint(69.311656, 41.279847), 4326), NULL),
  (900016, 900016, 'Uy Qurilish', 'Янги Сергели кўчаси, 72, Сергели район, Ташкент', '998338060755', 'universal', ST_SetSRID(ST_MakePoint(69.218801, 41.217415), 4326), NULL),
  (900017, 900017, 'Строй Плюс', 'Кўкча Дарвоза кўчаси, 3, Шайхантахур район, Ташкент', '998935581118', 'universal', ST_SetSRID(ST_MakePoint(69.223833, 41.324708), 4326), NULL),
  (900018, 900018, 'Олтин Уста', 'Чорсу майдони, 64, Алмазар район, Ташкент', '998938509861', 'universal', ST_SetSRID(ST_MakePoint(69.210954, 41.354256), 4326), NULL),
  (900019, 900019, 'Mehnat Savdo', 'Шота Руставели кўчаси, 7, Мирабад район, Ташкент', '998976733524', 'universal', ST_SetSRID(ST_MakePoint(69.280852, 41.275001), 4326), NULL),
  (900020, 900020, 'Строй Хауз', 'Фарход кўчаси, 34, Учтепа район, Ташкент', '998977246152', 'universal', ST_SetSRID(ST_MakePoint(69.181915, 41.292003), 4326), NULL),
  (900021, 900021, 'Qurilish Olami', 'Бобур кўчаси, 34, Яккасарай район, Ташкент', '998900507168', 'universal', ST_SetSRID(ST_MakePoint(69.247675, 41.285954), 4326), NULL),
  (900022, 900022, 'Зодчий', 'Бектемир кўчаси, 58, Бектемир район, Ташкент', '998956148085', 'universal', ST_SetSRID(ST_MakePoint(69.336741, 41.224241), 4326), NULL),
  (900023, 900023, 'Barkamol Baza', 'Катартал кўчаси, 4, Чиланзар район, Ташкент', '998994865275', 'universal', ST_SetSRID(ST_MakePoint(69.206220, 41.268312), 4326), NULL),
  (900024, 900024, 'Строй Актив', 'Амира Темура кўчаси, 87, Юнусабад район, Ташкент', '998955081786', 'universal', ST_SetSRID(ST_MakePoint(69.287461, 41.372175), 4326), NULL),
  (900025, 900025, 'Yangi Uy', 'Мустақиллик шоҳ кўчаси, 39, Мирзо-Улугбек район, Ташкент', '998919785313', 'universal', ST_SetSRID(ST_MakePoint(69.348671, 41.337139), 4326), NULL),
  (900026, 900026, 'Диёр Строй', 'Авиасозлар кўчаси, 1, Яшнабад район, Ташкент', '998979190970', 'universal', ST_SetSRID(ST_MakePoint(69.321272, 41.299686), 4326), NULL),
  (900027, 900027, 'Сантехника Плюс', 'Сергели 7-квартал, 18, Сергели район, Ташкент', '998334469815', 'plumbing', ST_SetSRID(ST_MakePoint(69.233265, 41.227082), 4326), NULL),
  (900028, 900028, 'Suv Tizimi', 'Кўкча Дарвоза кўчаси, 30, Шайхантахур район, Ташкент', '998997559388', 'plumbing', ST_SetSRID(ST_MakePoint(69.219870, 41.326963), 4326), NULL),
  (900029, 900029, 'Аква Дом', 'Чорсу майдони, 42, Алмазар район, Ташкент', '998996201997', 'plumbing', ST_SetSRID(ST_MakePoint(69.213801, 41.353574), 4326), CURRENT_TIMESTAMP + INTERVAL '30 days'),
  (900030, 900030, 'Santexnika Baza', 'Нукус кўчаси, 87, Мирабад район, Ташкент', '998996232735', 'plumbing', ST_SetSRID(ST_MakePoint(69.276223, 41.289041), 4326), NULL),
  (900031, 900031, 'Водолей', 'Фарход кўчаси, 57, Учтепа район, Ташкент', '998883498246', 'plumbing', ST_SetSRID(ST_MakePoint(69.176784, 41.296207), 4326), NULL),
  (900032, 900032, 'Suv Savdo', 'Кичик Бешёғоч кўчаси, 66, Яккасарай район, Ташкент', '998903833821', 'plumbing', ST_SetSRID(ST_MakePoint(69.250460, 41.290445), 4326), NULL),
  (900033, 900033, 'Сантех Маркет', 'Саноат кўчаси, 84, Бектемир район, Ташкент', '998335643125', 'plumbing', ST_SetSRID(ST_MakePoint(69.324590, 41.211308), 4326), NULL),
  (900034, 900034, 'Aqua Master', 'Катартал кўчаси, 83, Чиланзар район, Ташкент', '998947976879', 'plumbing', ST_SetSRID(ST_MakePoint(69.212210, 41.285151), 4326), NULL),
  (900035, 900035, 'Труба Дом', 'Амира Темура кўчаси, 77, Юнусабад район, Ташкент', '998337990331', 'plumbing', ST_SetSRID(ST_MakePoint(69.294936, 41.356115), 4326), NULL),
  (900036, 900036, 'Sanitar Savdo', 'Феруза кўчаси, 55, Мирзо-Улугбек район, Ташкент', '998987699658', 'plumbing', ST_SetSRID(ST_MakePoint(69.328691, 41.317983), 4326), NULL),
  (900037, 900037, 'Сантехмир', 'Авиасозлар кўчаси, 31, Яшнабад район, Ташкент', '998951824224', 'plumbing', ST_SetSRID(ST_MakePoint(69.330758, 41.288288), 4326), NULL),
  (900038, 900038, 'Suv Uyi', 'Қуруқсой кўчаси, 11, Сергели район, Ташкент', '998936591160', 'plumbing', ST_SetSRID(ST_MakePoint(69.205245, 41.226531), 4326), NULL),
  (900039, 900039, 'Аква Лайн', 'Кўкча Дарвоза кўчаси, 67, Шайхантахур район, Ташкент', '998971226143', 'plumbing', ST_SetSRID(ST_MakePoint(69.218548, 41.315764), 4326), NULL),
  (900040, 900040, 'Sant Market', 'Фаробий кўчаси, 18, Алмазар район, Ташкент', '998975485958', 'plumbing', ST_SetSRID(ST_MakePoint(69.214095, 41.348884), 4326), NULL),
  (900041, 900041, 'Пиломатериалы Ташкент', 'Шота Руставели кўчаси, 32, Мирабад район, Ташкент', '998919971762', 'wood', ST_SetSRID(ST_MakePoint(69.286039, 41.289293), 4326), NULL),
  (900042, 900042, 'Yog''och Savdo', 'Кичик Халқа Йўли, 55, Учтепа район, Ташкент', '998947824374', 'wood', ST_SetSRID(ST_MakePoint(69.169749, 41.302269), 4326), CURRENT_TIMESTAMP + INTERVAL '30 days'),
  (900043, 900043, 'Дерево Дом', 'Шайхонтоҳур кўчаси, 64, Яккасарай район, Ташкент', '998906003705', 'wood', ST_SetSRID(ST_MakePoint(69.258734, 41.277061), 4326), NULL),
  (900044, 900044, 'Taxta Baza', 'Бектемир кўчаси, 20, Бектемир район, Ташкент', '998994077687', 'wood', ST_SetSRID(ST_MakePoint(69.338135, 41.221857), 4326), NULL),
  (900045, 900045, 'Лес Строй', 'Катартал кўчаси, 7, Чиланзар район, Ташкент', '998883365609', 'wood', ST_SetSRID(ST_MakePoint(69.216061, 41.270819), 4326), NULL),
  (900046, 900046, 'Обои Дом', 'Амира Темура кўчаси, 36, Юнусабад район, Ташкент', '998940180995', 'wallpaper', ST_SetSRID(ST_MakePoint(69.295436, 41.357036), 4326), NULL),
  (900047, 900047, 'Oboi Market', 'Феруза кўчаси, 8, Мирзо-Улугбек район, Ташкент', '998901849717', 'wallpaper', ST_SetSRID(ST_MakePoint(69.319770, 41.341491), 4326), CURRENT_TIMESTAMP + INTERVAL '30 days'),
  (900048, 900048, 'Декор Стиль', 'Махтумқули кўчаси, 28, Яшнабад район, Ташкент', '998915803608', 'wallpaper', ST_SetSRID(ST_MakePoint(69.323025, 41.300925), 4326), NULL),
  (900049, 900049, 'Devor Bezak', 'Янги Сергели кўчаси, 22, Сергели район, Ташкент', '998991976622', 'wallpaper', ST_SetSRID(ST_MakePoint(69.210716, 41.230093), 4326), NULL),
  (900050, 900050, 'Обои Плюс', 'Зарқайнар кўчаси, 25, Шайхантахур район, Ташкент', '998990443008', 'wallpaper', ST_SetSRID(ST_MakePoint(69.237848, 41.332248), 4326), NULL);

-- ---------------------------------------------------------------- базовые цены
-- Одна цена на позицию каталога - средняя по ташкентскому рынку. Магазинная цена получается
-- умножением на множитель магазина ниже и округлением шагом, пропорциональным цене: сотня до
-- 5 000 сум, полтысячи до 50 000, тысяча дальше. **Шаг важен, а не косметичен** - округление
-- дюбеля за 800 сум до ближайших 500 давало ±50% на ровном месте, и отчёт об аномалиях
-- наполнялся товарами, с которыми всё в порядке.
CREATE TEMP TABLE demo_base_price (template_key VARCHAR(60) PRIMARY KEY, price BIGINT) ON COMMIT DROP;

INSERT INTO demo_base_price (template_key, price) VALUES
  ('universal.tape_45x50', 14000),
  ('universal.tape_45x40', 12000),
  ('universal.tape_double_sided_20', 10000),
  ('universal.gloves', 7000),
  ('universal.sandpaper_cloth', 12000),
  ('universal.sandpaper_holder', 25000),
  ('universal.grinding_disc_50', 18000),
  ('universal.grinding_disc_1000', 18000),
  ('universal.grinding_disc_1500', 19000),
  ('universal.diamond_disc_adp_125', 45000),
  ('universal.diamond_disc_ads_125', 47000),
  ('universal.diamond_disc_adm_125', 52000),
  ('universal.cutting_disc_luga_180', 12000),
  ('universal.cutting_disc_epa_125', 8000),
  ('universal.saw_disc_epa_180', 55000),
  ('universal.core_bit_25', 65000),
  ('universal.core_bit_75', 110000),
  ('universal.metal_drill_6', 9000),
  ('universal.sds_drill_6x120', 18000),
  ('universal.sds_drill_10x350', 38000),
  ('universal.screwdriver_bit_ph2', 6000),
  ('universal.screwdriver_06x4', 12000),
  ('universal.spatula_250', 20000),
  ('universal.spatula_400', 28000),
  ('universal.wrench_10', 18000),
  ('universal.wrench_19', 26000),
  ('universal.hammer_rubber', 32000),
  ('universal.hammer_steel_1kg', 48000),
  ('universal.utility_knife_18', 12000),
  ('universal.utility_blades_18', 9000),
  ('universal.tape_measure_5m', 28000),
  ('universal.tape_measure_10m', 45000),
  ('universal.foam_gun', 65000),
  ('universal.sealant_gun', 35000),
  ('universal.builders_line', 8000),
  ('universal.welding_mask', 190000),
  ('universal.welding_electrodes_3', 22000),
  ('universal.switch_2g_flush', 22000),
  ('universal.switch_2g_surface', 20000),
  ('universal.socket_2g_flush', 26000),
  ('universal.socket_2g_surface', 24000),
  ('universal.socket_box_ring', 3000),
  ('universal.led_lamp_10w', 14000),
  ('universal.led_lamp_60w', 32000),
  ('universal.lamp_holder', 6000),
  ('universal.led_panel_recessed_square_24w', 62000),
  ('universal.led_panel_recessed_round_24w', 60000),
  ('universal.led_panel_surface_square_24w', 68000),
  ('universal.led_panel_surface_round_24w', 66000),
  ('universal.extension_block_3', 18000),
  ('universal.plug_16a', 9000),
  ('universal.cable_pvs_2x15_white', 7500),
  ('universal.cable_pvs_2x15_black', 7500),
  ('universal.cable_pvs_2x25_black', 11000),
  ('universal.insulating_tape', 5000),
  ('universal.screws', 26000),
  ('universal.screws_drill_16', 28000),
  ('universal.screws_roofing', 32000),
  ('universal.nails', 18000),
  ('universal.bolts_galvanized', 30000),
  ('universal.nuts_galvanized', 28000),
  ('universal.washers_galvanized', 26000),
  ('universal.anchor_bolt_10x120', 7000),
  ('universal.anchor_frame_10x112', 5500),
  ('universal.dowel_6x60', 800),
  ('universal.dowel_umbrella_10x120', 1200),
  ('universal.dowel_screw_6x60', 30000),
  ('universal.dowel_nail', 28000),
  ('universal.powder_nails_27', 55000),
  ('universal.cable_tie_white_250', 22000),
  ('universal.cable_tie_black_250', 22000),
  ('universal.padlock_70', 45000),
  ('universal.rotband_25', 68000),
  ('universal.fugen_25', 78000),
  ('universal.tile_glue_megamix_22', 42000),
  ('universal.putty_eleron_01', 48000),
  ('universal.putty_eleron_05', 52000),
  ('universal.putty_eleron_001', 62000),
  ('universal.foam_tytan_65', 42000),
  ('universal.silicone_akfix_100e', 26000),
  ('universal.glue_tytan_classic_fix', 38000),
  ('universal.glue_akfix_705', 32000),
  ('universal.pva_eron', 16000),
  ('universal.enamel_hayat_pf115', 34000),
  ('universal.tint_palizh', 12000),
  ('universal.tint_pufamix', 18000),
  ('universal.solvent_646', 20000),
  ('universal.thinner', 15000),
  ('universal.brush_3', 18000),
  ('universal.brush_4', 24000),
  ('universal.masking_film_180', 28000),
  ('universal.drywall_wall', 62000),
  ('universal.drywall_ceiling', 55000),
  ('universal.drywall_moisture', 88000),
  ('universal.tile_leveling_clip_14', 45000),
  ('universal.tile_leveling_wedge_14', 32000),
  ('universal.roll_insulation_03', 180000),
  ('universal.roll_insulation_05', 240000),
  ('universal.film_black_06', 9000),
  ('universal.film_white_06', 9500),
  ('wood.beam_50x100', 180000),
  ('wood.board_25x150', 120000),
  ('wood.batten_30x40', 12000),
  ('wood.plywood_18', 320000),
  ('wood.rafter_50x150', 280000),
  ('wallpaper.premium_ru', 180000),
  ('wallpaper.premium_cn', 150000),
  ('wallpaper.premium_uz', 120000),
  ('wallpaper.standard_uz_1', 85000),
  ('wallpaper.standard_uz_2', 90000),
  ('wallpaper.standard_ru_1', 110000),
  ('wallpaper.standard_ru_2', 115000),
  ('wallpaper.econom_uz', 55000),
  ('wallpaper.econom_cn_1', 60000),
  ('wallpaper.econom_cn_2', 65000);

-- Сантехника - сто позиций одного поставщика, поэтому цена берётся правилом по названию, а
-- разброс внутри правила даёт хеш ключа: соседние фитинги не стоят одинаково.
INSERT INTO demo_base_price (template_key, price)
SELECT t.template_key,
       (ROUND(rule.price * (0.90 + (ABS(HASHTEXT(t.template_key)) % 21) / 100.0)
              / rule.step) * rule.step)::bigint
FROM product_templates t
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN t.name ILIKE '%Электрический смеситель%'      THEN 480000
        WHEN t.name ILIKE '%смеситель%'                    THEN 380000
        WHEN t.name ILIKE '%Канализационная труба%150/3%'  THEN 180000
        WHEN t.name ILIKE '%Канализационная труба%100/3%'  THEN 110000
        WHEN t.name ILIKE '%Канализационная труба%75/3%'   THEN  85000
        WHEN t.name ILIKE '%Канализационная труба%'        THEN  60000
        WHEN t.name ILIKE '%Лейка%'                        THEN  45000
        WHEN t.name ILIKE '%Шланг%'                        THEN  32000
        WHEN t.name ILIKE '%Термофлекс%'                   THEN  12000
        WHEN t.name ILIKE '%нержавейка%'                   THEN  42000
        WHEN t.name ILIKE '%латунн%'                       THEN  38000
        WHEN t.name ILIKE '%Эксцентрик%'                   THEN  22000
        WHEN t.name ILIKE '%Кальсо%'                       THEN  18000
        WHEN t.name ILIKE '%Бочонок%'                      THEN  12000
        WHEN t.name ILIKE '%Штуцер%'                       THEN   9000
        WHEN t.name ILIKE '%Удлинитель%'                   THEN   8000
        WHEN t.name ILIKE '%Хомут%'                        THEN   6000
        WHEN t.name ILIKE '%Клипса%'                       THEN   2500
        WHEN t.name ILIKE '%Заглушка%'                     THEN   4500
        WHEN t.name ILIKE 'VERO (к)%'                      THEN  22000
        WHEN t.name ILIKE 'VERO%'                          THEN   9000
        ELSE 12000
    END AS price,
    CASE
        WHEN t.name ILIKE '%Клипса%' OR t.name ILIKE '%Заглушка%' THEN 100
        WHEN t.name ILIKE '%смеситель%' OR t.name ILIKE '%Канализационная труба%' THEN 1000
        ELSE 500
    END AS step
) rule
WHERE t.shop_category = 'plumbing';

-- ---------------------------------------------------------------- множители
-- Ровный разброс внутри каждого рынка: часть магазинов дешевле среднего, часть дороже. Без него
-- у всех выходит индекс 100 и значок «на N% дешевле рынка» нечего показывать.
CREATE TEMP TABLE demo_shop_factor (shop_id BIGINT PRIMARY KEY, factor NUMERIC) ON COMMIT DROP;

INSERT INTO demo_shop_factor (shop_id, factor) VALUES
  (112, 1.04),
  (114, 1.098),
  (115, 1.046),
  (116, 1.076),
  (900001, 0.89),
  (900002, 1.1),
  (900003, 1.15),
  (900004, 1.05),
  (900005, 0.95),
  (900006, 1.08),
  (900007, 0.9),
  (900008, 1.12),
  (900009, 0.93),
  (900010, 1.14),
  (900011, 1.11),
  (900012, 1.0),
  (900013, 0.96),
  (900014, 1.07),
  (900015, 0.92),
  (900016, 0.97),
  (900017, 0.91),
  (900018, 1.01),
  (900019, 1.13),
  (900020, 0.94),
  (900021, 1.06),
  (900022, 0.98),
  (900023, 1.03),
  (900024, 1.02),
  (900025, 0.99),
  (900026, 1.09),
  (900027, 1.131),
  (900028, 1.057),
  (900029, 0.946),
  (900030, 0.964),
  (900031, 1.15),
  (900032, 0.909),
  (900033, 0.89),
  (900034, 0.983),
  (900035, 1.113),
  (900036, 1.039),
  (900037, 1.001),
  (900038, 1.094),
  (900039, 0.927),
  (900040, 1.02),
  (900041, 1.046),
  (900042, 0.89),
  (900043, 0.994),
  (900044, 1.15),
  (900045, 0.942),
  (900046, 0.89),
  (900047, 1.15),
  (900048, 0.942),
  (900049, 1.098),
  (900050, 0.994);

-- ---------------------------------------------------------------- товары
-- Один оператор на все пятьдесят магазинов: триггер индекса корзины работает на уровне
-- оператора, поэтому рынок пересчитывается по разу на категорию, а не по разу на строку.
INSERT INTO products (shop_id, template_key, name, category, unit, price, availability, image_path)
SELECT s.id, t.template_key, t.name, t.category, t.unit,
       (ROUND(b.price * f.factor / st.step) * st.step)::bigint,
       CASE WHEN ABS(HASHTEXT(t.template_key || s.id::text)) % 25 = 0 THEN 'on_order' ELSE 'in_stock' END,
       t.image_path
FROM shops s
JOIN product_templates t ON t.shop_category = s.category
JOIN demo_shop_factor f  ON f.shop_id = s.id
JOIN demo_base_price b   ON b.template_key = t.template_key
CROSS JOIN LATERAL (SELECT CASE WHEN b.price < 5000 THEN 100
                                WHEN b.price < 50000 THEN 500
                                ELSE 1000 END AS step) st
WHERE s.id BETWEEN 900001 AND 900999;

-- Магазины основателя уже существуют со скопированным прайсом. Их каталожные цены
-- перезаписываются при каждом прогоне - это тоже демонстрационные магазины.
UPDATE products p
SET price = (ROUND(b.price * f.factor
              / (CASE WHEN b.price < 5000 THEN 100 WHEN b.price < 50000 THEN 500 ELSE 1000 END))
            * (CASE WHEN b.price < 5000 THEN 100 WHEN b.price < 50000 THEN 500 ELSE 1000 END))::bigint,
    updated_at = CURRENT_TIMESTAMP
FROM demo_base_price b, demo_shop_factor f
WHERE p.shop_id IN (112, 114, 115, 116)
  AND p.template_key = b.template_key
  AND f.shop_id = p.shop_id;

-- ---------------------------------------------------------------- три опечатки
-- Владелец промахнулся на ноль. Отчёт об аномалиях в админке существует ровно ради таких строк,
-- и пустой отчёт на показе выглядит как ненужная функция. Позиции выбраны дешёвые: отклонение
-- видно сразу, а на корзину магазина лишний ноль почти не влияет.
UPDATE products SET price = price * 10
WHERE (shop_id, template_key) IN (
    (900007, 'universal.dowel_6x60'),
    (900019, 'universal.socket_box_ring'),
    (900022, 'universal.insulating_tape')
);

COMMIT;
