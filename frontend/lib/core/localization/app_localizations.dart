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

  // home screen
  String get searchHint => isRu ? 'Поиск...' : 'Qidirish...';
  String get shopsNearbyTitle => isRu ? 'Магазины рядом с вами' : "Sizga yaqin do'konlar";
  String get popularCategories => isRu ? 'Популярные категории' : 'Mashhur kategoriyalar';
  String get seeAll => isRu ? 'Все' : 'Hammasi';
  String get popularShops => isRu ? 'Популярные магазины' : "Mashhur do'konlar";
  String get viewAll => isRu ? 'Смотреть все' : "Hammasini ko'rish";
  String get averageCheck => isRu ? 'Средний чек:' : "O'rtacha hisob:";
  String get nearbyDistanceAway => isRu ? 'км' : 'km';

  // placeholder construction categories for the home grid, until the backend serves a real list.
  // they live here rather than inline in the widget because they were hardcoded in russian, which
  // meant switching the app to uzbek left this whole section untranslated.
  String get categoryMixes => isRu ? 'Смеси' : 'Aralashmalar';
  String get categoryBlocks => isRu ? 'Блоки' : 'Bloklar';
  String get categoryFasteners => isRu ? 'Крепёж' : 'Mahkamlagichlar';
  String get categoryRoofing => isRu ? 'Кровля' : 'Tom yopish';
  String get categoryElectrical => isRu ? 'Электрика' : 'Elektrika';
  String get categoryPlumbing => isRu ? 'Сантехника' : 'Santexnika';
  String get categoryPaints => isRu ? 'Краски' : "Bo'yoqlar";
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
  String get cityName => isRu ? 'Ташкент' : 'Toshkent';

  // placeholder screens
  String get messagesComingSoon => isRu
      ? 'Раздел сообщений скоро будет доступен'
      : "Xabarlar bo'limi tez orada bo'ladi";
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

  // shop upload screen (opened by tapping a shop in the my-shops list above)
  String get uploadScreenTitle => isRu ? 'Загрузка товаров' : "Mahsulotlarni yuklash";
  String get uploadInstructions => isRu
      ? 'Загрузите файл Excel (.xlsx) — до 50 товаров за раз. Повторная загрузка обновит существующие товары по артикулу, а не создаст дубликаты.'
      : "Excel (.xlsx) faylini yuklang — bir martada 50 tagacha mahsulot. Qayta yuklash mavjud mahsulotlarni artikul bo'yicha yangilaydi, dublikat yaratmaydi.";
  String get fileFormatTitle => isRu ? 'Формат файла' : "Fayl formati";
  String get fileFormatHint => isRu
      ? 'Первая строка — заголовки, столбцы строго в этом порядке:'
      : "Birinchi qator — sarlavhalar, ustunlar aynan shu tartibda:";
  String get skippedRowsHint => isRu
      ? 'Строки с пропущенными или некорректными данными пропускаются, остальные загружаются.'
      : "Ma'lumotlari to'liq bo'lmagan qatorlar o'tkazib yuboriladi, qolganlari yuklanadi.";
  String get pickFileButton => isRu ? 'Выбрать файл Excel' : "Excel faylini tanlash";
  String get pickFileHint => isRu ? 'Формат .xlsx, до 5 МБ' : ".xlsx formati, 5 MB gacha";

  // the six columns the upload expects, in order, each with a realistic example. shown on the
  // upload screen because an owner has no other way to discover the required layout - the backend
  // just skips rows it can't read (see parseProductRow in backend/internal/endpoints/products.go).
  List<({String header, String example})> get productColumnSpec => isRu
      ? const [
          (header: 'Категория', example: 'Цемент'),
          (header: 'Наименование товара', example: 'Цемент М400, 50 кг'),
          (header: 'Цена (сум)', example: '45 000'),
          (header: 'Единица измерения', example: 'шт'),
          (header: 'Наличие', example: 'Есть / Под заказ / Нет'),
          (header: 'Артикул', example: 'ART-001'),
        ]
      : const [
          (header: 'Kategoriya', example: 'Sement'),
          (header: 'Mahsulot nomi', example: 'Sement M400, 50 kg'),
          (header: "Narxi (so'm)", example: '45 000'),
          (header: "O'lchov birligi", example: 'dona'),
          (header: 'Mavjudligi', example: "Есть / Под заказ / Нет"),
          (header: 'Artikul', example: 'ART-001'),
        ];
  String get uploadingLabel => isRu ? 'Загрузка...' : "Yuklanmoqda...";
  String get uploadDoneTitle => isRu ? 'Файл обработан' : "Fayl qayta ishlandi";
  String get uploadNothingTitle =>
      isRu ? 'Ни один товар не загружен' : "Hech qanday mahsulot yuklanmadi";
  String get uploadNothingHint => isRu
      ? 'Проверьте порядок столбцов и заполненность строк в файле.'
      : "Fayldagi ustunlar tartibi va qatorlar to'liqligini tekshiring.";
  String get uploadStatRows => isRu ? 'Строк в файле' : "Faylda qator";
  String get uploadStatProcessed => isRu ? 'Загружено' : "Yuklandi";
  String get uploadStatSkipped => isRu ? 'Пропущено' : "O'tkazildi";

  // upload failures - keyed off the backend's machine-readable `code` (see writeUploadError in
  // backend/internal/endpoints/products.go) so users never see its english error strings
  String uploadErrorMessage(String code, {int? limit}) {
    switch (code) {
      case 'too_many_rows':
        final max = limit ?? 50;
        return isRu
            ? 'В файле больше $max товаров. Разделите его на несколько файлов.'
            : "Faylda $max tadan ko'p mahsulot bor. Uni bir nechta faylga bo'ling.";
      case 'file_too_large':
        return isRu
            ? 'Файл слишком большой. Максимум 5 МБ.'
            : "Fayl juda katta. Maksimal 5 MB.";
      case 'invalid_file':
        return isRu
            ? 'Не удалось прочитать файл. Убедитесь, что это .xlsx.'
            : "Faylni o'qib bo'lmadi. U .xlsx ekaniga ishonch hosil qiling.";
      case 'not_owner':
      case 'forbidden_role':
        return isRu
            ? 'У вас нет прав на загрузку товаров в этот магазин.'
            : "Bu do'konga mahsulot yuklash huquqingiz yo'q.";
      case 'shop_not_found':
        return isRu ? 'Магазин не найден.' : "Do'kon topilmadi.";
      case 'unauthorized':
        return isRu
            ? 'Сессия истекла. Войдите в аккаунт заново.'
            : "Seans tugadi. Hisobingizga qayta kiring.";
      default:
        return isRu
            ? 'Не удалось загрузить файл. Проверьте подключение и попробуйте снова.'
            : "Faylni yuklab bo'lmadi. Ulanishni tekshirib, qayta urinib ko'ring.";
    }
  }

  String get fileNotReadable => isRu
      ? 'Не удалось открыть выбранный файл. Попробуйте другой.'
      : "Tanlangan faylni ochib bo'lmadi. Boshqasini tanlang.";

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
