import 'package:flutter/material.dart';

enum AppLanguage {
  ru('Русский', 'ru'),
  uz("O'zbekcha", 'uz');

  const AppLanguage(this.displayName, this.code);

  final String displayName;
  final String code;
}

class AppLocalizations {
  AppLocalizations(this.language);

  final AppLanguage language;

  bool get isRu => language == AppLanguage.ru;

  Locale get locale => Locale(language.code);

  String get loginTitle => isRu ? 'Войти в аккаунт' : 'Hisobga kirish';
  String get loginSubtitle => isRu
      ? 'Находите магазины, сравнивайте предложения и развивайте свой бизнес!'
      : "Do'konlarni toping, takliflarni solishtiring va biznesingizni rivojlantiring!";
  String get loginButton => isRu
      ? 'Войти / Зарегистрироваться'
      : "Kirish / Ro'yxatdan o'tish";

  String get vendorBadge => isRu ? 'Продавец' : 'Sotuvchi';
  String get manageShops =>
      isRu ? 'Управление магазинами' : "Do'konlarni boshqarish";
  String get shopSettings =>
      isRu ? 'Настройка магазинов' : "Do'konlar sozlamalari";
  String get addStore => isRu ? 'Добавить новый магазин' : "Yangi do'kon qo'shish";
  String get backButton => isRu ? 'Назад в профиль' : 'Profilga qaytish';

  // collapses the shop-management accordion. deliberately not "back": the group expands in place
  // now instead of replacing the page, so nothing is being navigated away from.
  String get closeButton => isRu ? 'Закрыть' : 'Yopish';
  String get favorites => isRu ? 'Избранное' : 'Tanlanganlar';
  String get languageSettings => isRu ? 'Язык приложения' : 'Ilova tili';
  String get support => isRu ? 'Поддержка' : "Qo'llab-quvvatlash";
  String get logout => isRu ? 'Выйти из аккаунта' : 'Akkauntdan chiqish';
  String get selectLanguage => isRu ? 'Выберите язык' : 'Tilni tanlang';
  String get version => 'Domix • 1.0.0';

  String get registerTitle => isRu ? 'Регистрация' : "Ro'yxatdan o'tish";
  String get registerSubtitle => '';
  String get nameInputLabel => isRu ? 'Имя и фамилия' : "Ism va familiyangiz";
  String get nameRequiredError =>
      isRu ? 'Пожалуйста, введите имя' : "Iltimos, ismingizni kiriting";
  String get roleCustomer => isRu ? 'Покупатель' : "Xaridor";
  String get roleCustomerSub =>
      isRu ? 'Покупки и заказы' : "Xaridlar va buyurtmalar";
  String get roleVendor => isRu ? 'Продавец' : "Sotuvchi";
  String get roleVendorSub => isRu ? 'Мой магазин' : "Mening do'konim";
  String get continueTelegram => isRu
      ? 'Продолжить в Telegram'
      : "Telegram orqali kirish";
  String get welcomeMessage => isRu
      ? 'Добро пожаловать в Domix! 🎉'
      : "Domix'ga xush kelibsiz! 🎉";

  String get authWaitingTitle =>
      isRu ? 'Ожидание Telegram' : 'Telegram kutilmoqda';
  String get authWaitingDesc => isRu
      ? 'Пожалуйста, перейдите в Telegram, нажмите /start и поделитесь номером.'
      : "Iltimos, Telegram botga o'ting, /start tugmasini bosing va raqamni ulashing.";
  String get timerLabel =>
      isRu ? 'Время на подтверждение:' : 'Tasdiqlash uchun vaqt:';
  String get retryButton =>
      isRu ? 'Попробовать снова' : 'Qayta urinish';
  String get cancelButton => isRu ? 'Отменить' : 'Bekor qilish';
  String get timeoutError => isRu
      ? 'Время ожидания истекло. Попробуйте снова.'
      : 'Kutish vaqti tugadi. Qayta urinib ko\'ring.';

  // error dialog shown when the login attempt fails
  String get errorDialogTitle =>
      isRu ? 'Что-то пошло не так' : 'Nimadir xato ketdi';
  String get errorDialogInstructions => isRu
      ? 'Проверьте, что Telegram установлен и есть подключение к интернету, затем попробуйте снова.'
      : "Telegram o'rnatilganligini va internet aloqasi borligini tekshiring, so'ngra qayta urinib ko'ring.";
  String get okButton => isRu ? 'Понятно' : 'Tushunarli';

  // bottom navigation labels
  String get homeTab => isRu ? 'Главная' : 'Asosiy';
  // the search tab became the entry point for the planned job-ticket marketplace: clients post
  // construction work requests, workers pick them up. search itself now lives on the map and home.
  String get ticketsTab => isRu ? 'Заявки' : 'Buyurtmalar';
  String get mapTab => isRu ? 'Карта' : 'Xarita';
  String get messagesTab => isRu ? 'Сообщения' : 'Xabarlar';
  String get profileTab => isRu ? 'Профиль' : 'Profil';

  // home screen. the hint names what is actually searched (products) rather than the generic
  // "Поиск..." - a placeholder is the only instruction an empty field ever gets.
  String get searchHint => isRu ? 'Ищите товары...' : 'Mahsulotlarni qidiring...';
  /// shops ranked by the lowest average check across the whole catalogue - deliberately not a
  /// nearby/distance list, so the copy promises a price, not a location
  String get bestOffersTitle => isRu ? 'Лучшие предложения' : 'Eng yaxshi takliflar';
  String get popularCategories => isRu ? 'Популярные категории' : 'Mashhur kategoriyalar';
  String get seeAll => isRu ? 'Все' : 'Hammasi';

  // "VIP" stays latin in both languages on purpose - it is the name of the paid placement tier,
  // not a word being translated. only the noun after it follows the language.
  String get vipShops => isRu ? 'VIP Магазины' : "VIP Do'konlar";
  String get viewAll => isRu ? 'Смотреть все' : "Hammasini ko'rish";
  String get averageCheck => isRu ? 'Средний чек:' : "O'rtacha hisob:";

  // the twelve product categories, shown both as the home screen's "Популярные категории" grid and
  // as the options in the product form's category dropdown - one vocabulary, because they are the
  // same thing (see ProductCategory in features/products/data/product_category.dart).
  //
  // they live here rather than in the widget or the database because the stored value is a code
  // ('mixes', 'blocks', ...): when the display names were the stored values they were hardcoded
  // russian, and switching the app to uzbek left every category untranslated.
  String get categoryMixes => isRu ? 'Смеси' : 'Aralashmalar';
  String get categoryBlocks => isRu ? 'Кирпич и блоки' : "G'isht va bloklar";
  String get categoryLumber => isRu ? 'Пиломатериалы' : "Yog'och materiallar";
  String get categoryMetal => isRu ? 'Металлопрокат' : 'Metall prokat';
  String get categoryFasteners => isRu ? 'Крепёж' : 'Mahkamlagichlar';
  String get categoryRoofing => isRu ? 'Кровля' : 'Tom yopish';
  String get categoryInsulation => isRu ? 'Изоляция' : 'Izolyatsiya';
  String get categoryElectrical => isRu ? 'Электрика' : 'Elektrika';
  String get categoryPlumbing => isRu ? 'Сантехника' : 'Santexnika';
  String get categoryPaints => isRu ? 'Краски' : "Bo'yoqlar";
  String get categoryFinishing => isRu ? 'Отделка' : 'Pardozlash';
  String get categoryTools => isRu ? 'Инструменты' : 'Asboblar';
  String get currencySom => isRu ? 'сум' : "so'm";

  // "1250000" -> "1 250 000 сум" (or "so'm"). lives here rather than in one screen because the map
  // pin label, the shop card and the details sheet all show the same amount and must agree - a
  // plain no-dependency loop, since intl isn't a direct dependency of this project.
  String somAmount(int amount) {
    final digits = amount.abs().toString();
    final grouped = StringBuffer(amount < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(' ');
      grouped.write(digits[i]);
    }
    return '$grouped $currencySom';
  }
  /// the city shown in the home header before the user has ever picked one on the map
  String get cityName => isRu ? 'Ташкент' : 'Toshkent';

  /// tooltip/semantics for the header's city pill, which opens the map picker
  String get changeCityLabel => isRu ? 'Сменить город' : "Shaharni o'zgartirish";

  // notifications screen. empty for everyone right now - nothing in the app produces a
  // notification yet - so the screen exists to make the bell a real destination, not a dead icon.
  String get notificationsTitle => isRu ? 'Уведомления' : 'Bildirishnomalar';
  String get noNotifications => isRu ? 'Нет уведомлений' : "Bildirishnomalar yo'q";
  String get noNotificationsHint => isRu
      ? 'Здесь появятся новые заказы, ответы магазинов и новости Domix.'
      : "Bu yerda yangi buyurtmalar, do'konlar javoblari va Domix yangiliklari paydo bo'ladi.";

  // placeholder screens. these read as a title plus a line of "what will appear here", the shape
  // EmptyStateView wants - the messages tab used to be one grey sentence floating on the page,
  // which is why it looked unfinished next to Заявки.
  String get messagesComingSoonTitle => isRu ? 'Сообщения' : 'Xabarlar';
  String get messagesComingSoonBody => isRu
      ? 'Здесь появится переписка с магазинами и мастерами — можно будет уточнить цену и наличие, не выходя из приложения.'
      : "Bu yerda do'konlar va ustalar bilan yozishmalar paydo bo'ladi — narx va mavjudlikni ilovadan chiqmasdan aniqlaysiz.";
  String get ticketsComingSoonTitle =>
      isRu ? 'Заявки мастерам' : 'Ustalarga buyurtmalar';
  String get ticketsComingSoonBody => isRu
      ? 'Скоро здесь можно будет оставить заявку на работу, а мастера и бригады будут откликаться на неё.'
      : "Tez orada bu yerda ish uchun buyurtma qoldirasiz, ustalar va brigadalar unga javob beradi.";
  String get comingSoonBadge => isRu ? 'Скоро' : 'Tez orada';

  // map screen (shop pins)
  String get noShopsYet => isRu ? 'Пока нет магазинов' : "Hozircha do'konlar yo'q";
  String get mapLoadError =>
      isRu ? 'Не удалось загрузить магазины' : "Do'konlarni yuklab bo'lmadi";
  String get loadingShops => isRu ? 'Загружаем магазины...' : "Do'konlar yuklanmoqda...";

  // map search. the panel searches two sources at once, so its results are grouped and labelled -
  // a shop the app already knows about and a geocoded address are not the same kind of answer.
  String get mapSearchHint =>
      isRu ? 'Магазин или адрес' : "Do'kon yoki manzil";
  String get searchSectionShops => isRu ? 'Магазины' : "Do'konlar";
  String get searchSectionPlaces => isRu ? 'Адреса' : 'Manzillar';
  String get searchNoResults => isRu ? 'Ничего не найдено' : 'Hech narsa topilmadi';
  String get searchClear => isRu ? 'Очистить' : 'Tozalash';

  // shop details sheet. the phone number is shown as a labelled detail row now, so the call button
  // can carry a short verb instead of the raw number - a cta reads better as an action than as data.
  String get addressLabel => isRu ? 'Адрес' : 'Manzil';
  String get phoneLabel => isRu ? 'Телефон' : 'Telefon';
  String get callButton => isRu ? 'Позвонить' : "Qo'ng'iroq qilish";

  // compact form of averageCheck, for rows where the full label would crowd the number out.
  // "Ср." was too clipped to read at a glance next to a number - "Сред." costs three pixels.
  String get averageCheckShort => isRu ? 'Сред. чек' : "O'rt. hisob";

  // location picker screen
  String get searchLocationHint => isRu ? 'Поиск адреса...' : "Manzilni qidirish...";
  String get resolvingAddress => isRu ? 'Определяем адрес...' : "Manzil aniqlanmoqda...";
  String get confirmLocationButton =>
      isRu ? 'Подтвердить местоположение' : "Joylashuvni tasdiqlash";

  // add store screen
  String get addStoreScreenTitle => isRu ? 'Добавить магазин' : "Do'kon qo'shish";
  String get shopNameLabel => isRu ? 'Название магазина' : "Do'kon nomi";
  String get shopNameRequiredError =>
      isRu ? 'Пожалуйста, введите название магазина' : "Iltimos, do'kon nomini kiriting";
  String get contactPhoneLabel => isRu ? 'Контактный номер' : "Aloqa uchun raqam";
  String get contactPhoneRequiredError =>
      isRu ? 'Пожалуйста, введите контактный номер' : "Iltimos, aloqa raqamini kiriting";
  String get locationLabel => isRu ? 'Местоположение' : "Joylashuv";
  String get pickLocationPrompt =>
      isRu ? 'Выбрать местоположение на карте' : "Xaritada joylashuvni tanlash";
  String get changeLocationButton => isRu ? 'Изменить' : "O'zgartirish";
  String get locationRequiredError =>
      isRu ? 'Пожалуйста, выберите местоположение на карте' : "Iltimos, xaritada joylashuvni tanlang";
  // shop category, picked on the add-store form. it decides which ready-made product catalogue the
  // backend seeds the new shop with, which is why the picker leads with how many products that is -
  // it is the concrete thing the owner gets out of the choice.
  String get shopCategoryLabel => isRu ? 'Категория магазина' : "Do'kon turi";
  String get pickCategoryPrompt =>
      isRu ? 'Выберите категорию магазина' : "Do'kon turini tanlang";
  String get categoryRequiredError => isRu
      ? 'Пожалуйста, выберите категорию магазина'
      : "Iltimos, do'kon turini tanlang";
  String get shopCategoryPickerTitle =>
      isRu ? 'Категория магазина' : "Do'kon turi";
  String get shopCategoryPickerHint => isRu
      ? 'Каталог заполнится готовыми товарами сразу после создания — вам останется указать цены. Категорию нельзя изменить позже.'
      : "Katalog do'kon yaratilgandan so'ng tayyor mahsulotlar bilan to'ladi — sizga faqat narxlarni ko'rsatish qoladi. Turni keyin o'zgartirib bo'lmaydi.";

  String get shopCategoryUniversal => isRu ? 'Универсальный' : 'Universal';
  String get shopCategoryPlumbing => isRu ? 'Сантехника' : 'Santexnika';
  String get shopCategoryWood => isRu ? 'Дерево' : "Yog'och";
  String get shopCategoryWallpaper => isRu ? 'Обои' : 'Oboylar';

  String get shopCategoryUniversalHint => isRu
      ? 'Всё для стройки: смеси, блоки, крепёж, электрика'
      : "Qurilish uchun hammasi: aralashmalar, bloklar, mahkamlagichlar, elektrika";
  String get shopCategoryPlumbingHint => isRu
      ? 'Трубы, фитинги, смесители, отопление'
      : "Quvurlar, fitinglar, smesitellar, isitish";
  String get shopCategoryWoodHint => isRu
      ? 'Пиломатериалы, фанера, вагонка, ДСП'
      : "Yog'och materiallar, faner, vagonka, DSP";
  String get shopCategoryWallpaperHint => isRu
      ? 'Обои всех видов, клей, бордюры'
      : "Har xil oboylar, yelim, bordyurlar";

  /// "Готовый каталог: 50 товаров" - shown under each category in the picker
  String readyCatalogLabel(int count) => isRu
      ? 'Готовый каталог: ${productsCountLabel(count)}'
      : "Tayyor katalog: ${productsCountLabel(count)}";

  String get createStoreButton => isRu ? 'Создать магазин' : "Do'kon yaratish";
  String get storeCreatedMessage =>
      isRu ? 'Магазин успешно добавлен! 🎉' : "Do'kon muvaffaqiyatli qo'shildi! 🎉";
  String get storeCreationFailed => isRu
      ? 'Не удалось создать магазин. Проверьте подключение и попробуйте снова.'
      : "Do'konni yaratib bo'lmadi. Ulanishni tekshirib, qayta urinib ko'ring.";

  // my shops screen (list of shops the current owner has, opened from shopSettings above)
  String get myShopsScreenTitle => isRu ? 'Мои магазины' : "Mening do'konlarim";
  String get noOwnedShopsYet =>
      isRu ? 'У вас пока нет магазинов' : "Sizda hali do'konlar yo'q";
  String get noOwnedShopsHint => isRu
      ? 'Добавьте магазин, чтобы загрузить товары и появиться на карте'
      : "Mahsulot yuklash va xaritada ko'rinish uchun do'kon qo'shing";
  String get myShopsLoadError =>
      isRu ? 'Не удалось загрузить ваши магазины' : "Do'konlaringizni yuklab bo'lmadi";
  String get retryButtonShort => isRu ? 'Повторить' : "Qayta urinish";
  String get noProductsYet => isRu ? 'Нет товаров' : "Mahsulot yo'q";

  // "5 магазинов" / "5 ta do'kon" - russian picks its noun form by the number, uzbek doesn't
  String shopsCountLabel(int count) =>
      isRu ? '$count ${_ruPlural(count, 'магазин', 'магазина', 'магазинов')}' : "$count ta do'kon";
  String productsCountLabel(int count) =>
      isRu ? '$count ${_ruPlural(count, 'товар', 'товара', 'товаров')}' : '$count ta mahsulot';

  // shop settings hub (opened by tapping a shop in the my-shops list above). it is a menu of
  // sections rather than one long page, so each section here needs a title and a line saying what
  // is behind it - the owner picks from the list without opening anything to find out.
  String get shopSettingsScreenTitle => isRu ? 'Настройки магазина' : "Do'kon sozlamalari";
  String get sectionProductsTitle => isRu ? 'Товары' : 'Mahsulotlar';
  String get sectionProductsSubtitle => isRu
      ? 'Цены, наличие и свои товары'
      : "Narxlar, mavjudligi va o'z mahsulotlaringiz";
  String get sectionDetailsTitle => isRu ? 'Данные магазина' : "Do'kon ma'lumotlari";
  String get sectionDetailsSubtitle => isRu
      ? 'Название, телефон, адрес и удаление'
      : "Nomi, telefoni, manzili va o'chirish";

  // edit shop screen (the "Данные магазина" section above)
  String get editStoreScreenTitle => isRu ? 'Данные магазина' : "Do'kon ma'lumotlari";
  String get saveChangesButton => isRu ? 'Сохранить изменения' : "O'zgarishlarni saqlash";
  String get storeUpdatedMessage =>
      isRu ? 'Изменения сохранены' : "O'zgarishlar saqlandi";
  String get noChangesToSave =>
      isRu ? 'Вы ничего не изменили' : "Siz hech narsani o'zgartirmadingiz";

  // delete, kept in its own visually separated block at the bottom of the edit screen. it is the
  // one irreversible action in the app, so it gets a red section header rather than sitting in the
  // same list as "save".
  String get dangerZoneTitle => isRu ? 'Удаление' : "O'chirish";
  String get deleteStoreButton => isRu ? 'Удалить магазин' : "Do'konni o'chirish";
  String get deleteStoreHint => isRu
      ? 'Магазин исчезнет с карты вместе со всеми загруженными товарами. Действие необратимо.'
      : "Do'kon barcha yuklangan mahsulotlari bilan xaritadan yo'qoladi. Bu amalni qaytarib bo'lmaydi.";
  String get deleteStoreConfirmTitle =>
      isRu ? 'Удалить магазин?' : "Do'kon o'chirilsinmi?";
  String deleteStoreConfirmBody(String shopName, int productCount) {
    // naming the shop and counting what goes with it is the whole point of the dialog: "удалить?"
    // alone gives the owner nothing to check their intent against
    final products = productCount > 0
        ? (isRu
            ? ' и все его товары (${productsCountLabel(productCount)})'
            : " va uning barcha mahsulotlari (${productsCountLabel(productCount)})")
        : '';
    return isRu
        ? 'Магазин «$shopName»$products будет удалён безвозвратно. Это действие нельзя отменить.'
        : "«$shopName» do'koni$products butunlay o'chiriladi. Bu amalni bekor qilib bo'lmaydi.";
  }
  String get deleteStoreConfirmAction => isRu ? 'Удалить' : "O'chirish";
  String get storeDeletedMessage =>
      isRu ? 'Магазин удалён' : "Do'kon o'chirildi";

  // edit/delete failures - keyed off the backend's machine-readable `code` (see writeShopError in
  // backend/internal/endpoints/shops.go), same contract as productErrorMessage below
  String shopMutationErrorMessage(String code) {
    switch (code) {
      case 'not_owner':
      case 'forbidden_role':
        return isRu
            ? 'У вас нет прав на изменение этого магазина.'
            : "Bu do'konni o'zgartirish huquqingiz yo'q.";
      case 'shop_not_found':
        return isRu
            ? 'Магазин не найден — возможно, он уже удалён.'
            : "Do'kon topilmadi — ehtimol u allaqachon o'chirilgan.";
      case 'missing_fields':
        return isRu
            ? 'Заполните название, телефон и адрес.'
            : "Nomi, telefoni va manzilini to'ldiring.";
      case 'unauthorized':
        return isRu
            ? 'Сессия истекла. Войдите в аккаунт заново.'
            : "Seans tugadi. Hisobingizga qayta kiring.";
      default:
        return isRu
            ? 'Не удалось сохранить. Проверьте подключение и попробуйте снова.'
            : "Saqlab bo'lmadi. Ulanishni tekshirib, qayta urinib ko'ring.";
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // products: the catalogue grid the owner manages, and the same grid shown to a customer on a
  // shop's card. a shop is seeded with its category's template at creation, so most of these
  // strings are about the state that follows: rows that exist but have no price yet.
  // ───────────────────────────────────────────────────────────────────────────

  String get productsScreenTitle => isRu ? 'Товары' : 'Mahsulotlar';
  String get loadingProducts => isRu ? 'Загружаем товары...' : 'Mahsulotlar yuklanmoqda...';
  /// under the load-error title. a bare "не удалось загрузить" next to a retry button that keeps
  /// failing tells the owner nothing about whether the problem is theirs to fix; naming the two
  /// realistic causes at least points somewhere.
  String get productsLoadErrorHint => isRu
      ? 'Проверьте подключение к интернету. Если оно есть — сервер временно недоступен, попробуйте позже.'
      : "Internet aloqasini tekshiring. Aloqa bo'lsa — server vaqtincha ishlamayapti, keyinroq urinib ko'ring.";

  String get productsLoadError =>
      isRu ? 'Не удалось загрузить товары' : "Mahsulotlarni yuklab bo'lmadi";
  String get noProductsInShop =>
      isRu ? 'В магазине пока нет товаров' : "Do'konda hozircha mahsulot yo'q";
  String get noProductsInShopHint => isRu
      ? 'Добавьте свои товары кнопкой ниже.'
      : "Quyidagi tugma orqali o'z mahsulotlaringizni qo'shing.";

  /// on a product with no price yet. the single most important label on the owner's grid right
  /// after a shop is created - it is the whole to-do list.
  String get priceNotSet => isRu ? 'Цена не указана' : "Narx ko'rsatilmagan";

  /// "Цены указаны: 12 из 50" - the progress line at the top of the owner's grid
  String pricedProgressLabel(int priced, int total) => isRu
      ? 'Цены указаны: $priced из $total'
      : "Narxlar ko'rsatilgan: $total dan $priced";

  /// badge on a product the owner added themselves, as opposed to one from the category template
  String get ownProductBadge => isRu ? 'Свой товар' : "O'z mahsuloti";

  String get addProductButton => isRu ? 'Добавить товар' : "Mahsulot qo'shish";

  /// "Свои товары: 12 из 20" - how much of the own-products allowance is used
  String ownProductsUsedLabel(int used, int max) => isRu
      ? 'Свои товары: $used из $max'
      : "O'z mahsulotlaringiz: $max dan $used";
  String ownProductsLimitReachedHint(int max) => isRu
      ? 'Достигнут лимит в $max собственных товаров. Удалите один, чтобы добавить новый.'
      : "$max ta o'z mahsulotingiz chegarasiga yetdingiz. Yangisini qo'shish uchun bittasini o'chiring.";

  // add/edit one product
  String get addProductTitle => isRu ? 'Новый товар' : 'Yangi mahsulot';
  String get editProductTitle => isRu ? 'Редактировать товар' : "Mahsulotni tahrirlash";
  String get productNameLabel => isRu ? 'Наименование' : 'Nomi';
  String get productNameRequiredError =>
      isRu ? 'Введите наименование товара' : "Mahsulot nomini kiriting";
  String get productCategoryLabel => isRu ? 'Категория' : 'Kategoriya';
  String get productCategoryRequiredError =>
      isRu ? 'Выберите категорию товара' : "Mahsulot kategoriyasini tanlang";

  /// placeholder in the category dropdown before anything is chosen
  String get pickProductCategoryPrompt =>
      isRu ? 'Выберите категорию' : 'Kategoriyani tanlang';
  String get productPriceLabel => isRu ? 'Цена (сум)' : "Narxi (so'm)";
  String get productPriceHint =>
      isRu ? 'Оставьте пустым, если цены пока нет' : "Narx hali bo'lmasa, bo'sh qoldiring";
  String get productPriceInvalidError =>
      isRu ? 'Введите цену числом' : "Narxni raqam bilan kiriting";
  String get productUnitLabel => isRu ? 'Единица измерения' : "O'lchov birligi";
  String get productUnitRequiredError =>
      isRu ? 'Укажите единицу измерения' : "O'lchov birligini ko'rsating";
  String get productAvailabilityLabel => isRu ? 'Наличие' : 'Mavjudligi';
  String get saveProductButton => isRu ? 'Сохранить' : 'Saqlash';
  String get productSavedMessage => isRu ? 'Товар сохранён' : 'Mahsulot saqlandi';
  String get productDeletedMessage => isRu ? 'Товар удалён' : "Mahsulot o'chirildi";
  String get deleteProductButton => isRu ? 'Удалить товар' : "Mahsulotni o'chirish";
  String get deleteProductConfirmTitle =>
      isRu ? 'Удалить товар?' : "Mahsulot o'chirilsinmi?";
  String deleteProductConfirmBody(String productName) => isRu
      ? 'Товар «$productName» исчезнет из каталога магазина. Это действие нельзя отменить.'
      : "«$productName» mahsuloti do'kon katalogidan yo'qoladi. Bu amalni bekor qilib bo'lmaydi.";

  /// explains why a template product's name/category/unit are shown as plain text and why it has no
  /// delete button - without it, the missing controls read as a bug rather than as a rule
  String get templateProductHint => isRu
      ? 'Товар из готового каталога. Такие товары одинаковы во всех магазинах категории — поэтому здесь можно указать только цену и наличие, а удалить товар нельзя. Свои товары редактируются полностью.'
      : "Tayyor katalogdagi mahsulot. Bunday mahsulotlar kategoriyadagi barcha do'konlarda bir xil — shuning uchun bu yerda faqat narx va mavjudligini ko'rsatish mumkin, o'chirib bo'lmaydi. O'z mahsulotlaringiz to'liq tahrirlanadi.";

  /// badge over the read-only fields of a template product
  String get templateFieldLocked => isRu ? 'Не изменяется' : "O'zgarmaydi";

  // stock status. the codes behind these live in the database (backend/db/migrations/000004);
  // these are only ever the display side of them.
  String get availabilityInStock => isRu ? 'Есть' : 'Bor';
  String get availabilityOnOrder => isRu ? 'Под заказ' : 'Buyurtma asosida';
  String get availabilityUnavailable => isRu ? 'Нет' : "Yo'q";

  // customer-facing catalogue on a shop's card
  String get shopProductsSectionTitle => isRu ? 'Товары' : 'Mahsulotlar';
  String get noPricedProductsYet => isRu
      ? 'Магазин ещё не указал цены на товары'
      : "Do'kon hali mahsulot narxlarini ko'rsatmagan";

  // product add/edit/delete failures - keyed off the backend's machine-readable `code` (see
  // writeAPIError in backend/internal/endpoints/authz.go), same contract as the two above
  String productErrorMessage(String code, {int? limit}) {
    switch (code) {
      case 'product_limit_reached':
        final max = limit ?? 20;
        return isRu
            ? 'Можно добавить не больше $max собственных товаров.'
            : "$max tadan ko'p o'z mahsulotingizni qo'sha olmaysiz.";
      case 'template_product':
        return isRu
            ? 'Товар из готового каталога нельзя удалить.'
            : "Tayyor katalogdagi mahsulotni o'chirib bo'lmaydi.";
      case 'not_owner':
      case 'forbidden_role':
        return isRu
            ? 'У вас нет прав на изменение товаров этого магазина.'
            : "Bu do'kon mahsulotlarini o'zgartirish huquqingiz yo'q.";
      case 'product_not_found':
        return isRu
            ? 'Товар не найден — возможно, он уже удалён.'
            : "Mahsulot topilmadi — ehtimol u allaqachon o'chirilgan.";
      case 'shop_not_found':
        return isRu ? 'Магазин не найден.' : "Do'kon topilmadi.";
      case 'missing_fields':
        return isRu
            ? 'Заполните наименование, категорию и единицу измерения.'
            : "Nomi, kategoriyasi va o'lchov birligini to'ldiring.";
      case 'invalid_price':
        return isRu ? 'Некорректная цена.' : "Narx noto'g'ri.";
      case 'invalid_category':
        return isRu
            ? 'Выберите категорию из списка.'
            : "Ro'yxatdan kategoriyani tanlang.";
      case 'field_too_long':
        return isRu
            ? 'Одно из полей слишком длинное.'
            : "Maydonlardan biri juda uzun.";
      case 'unauthorized':
        return isRu
            ? 'Сессия истекла. Войдите в аккаунт заново.'
            : "Seans tugadi. Hisobingizga qayta kiring.";
      default:
        return isRu
            ? 'Не удалось сохранить. Проверьте подключение и попробуйте снова.'
            : "Saqlab bo'lmadi. Ulanishni tekshirib, qayta urinib ko'ring.";
    }
  }

  // russian noun agreement: 1 товар, 2-4 товара, 5+ товаров (with the 11-14 exception)
  String _ruPlural(int count, String one, String few, String many) {
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return many;
    switch (count % 10) {
      case 1:
        return one;
      case 2:
      case 3:
      case 4:
        return few;
      default:
        return many;
    }
  }
}
