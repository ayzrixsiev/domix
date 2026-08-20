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

  // account deletion. google play requires every app with accounts to offer this from inside the
  // app, and the wording matters as much as the button: the dialog has to name what disappears,
  // because for a shop owner that is their whole catalogue and not just a login.
  String get deleteAccount => isRu ? 'Удалить аккаунт' : "Akkauntni o'chirish";
  String get deleteAccountConfirmTitle =>
      isRu ? 'Удалить аккаунт?' : "Akkaunt o'chirilsinmi?";
  String get deleteAccountConfirmBody => isRu
      ? 'Ваш профиль, все ваши магазины и все их товары будут удалены безвозвратно. '
          'Это действие нельзя отменить.'
      : "Profilingiz, barcha do'konlaringiz va ulardagi barcha mahsulotlar butunlay o'chiriladi. "
          "Bu amalni bekor qilib bo'lmaydi.";
  String get deleteAccountConfirmAction => isRu ? 'Удалить' : "O'chirish";
  /// The headline over a failed deletion.
  ///
  /// It has its own, rather than reusing [errorDialogTitle] («Что-то пошло не так»), because that
  /// one comes paired with [errorDialogInstructions] - which is about Telegram. The profile screen
  /// printed that pair for a failed deletion for a while, so the app told a user whose account had
  /// not been deleted to go and check their Telegram installation.
  String get deleteAccountFailedTitle => isRu
      ? 'Не удалось удалить аккаунт'
      : "Akkauntni o'chirib bo'lmadi";
  String get deleteAccountFailed => isRu
      ? 'Не удалось удалить аккаунт. Проверьте соединение и попробуйте ещё раз.'
      : "Akkauntni o'chirib bo'lmadi. Aloqani tekshiring va qayta urinib ko'ring.";

  /// A timeout says something different from a failure, so it gets a different sentence.
  ///
  /// The request most likely *did* reach the server - deleting an account cascades through the
  /// user's shops and all of their products, which is the slowest write in the app - so the honest
  /// instruction is "press it again", not "check your connection". Pressing it again is safe:
  /// `DELETE /api/me` answers success for an account that is already gone.
  String get deleteAccountTimedOut => isRu
      ? 'Сервер не ответил вовремя. Нажмите «Удалить» ещё раз — повторное нажатие безопасно.'
      : "Server o'z vaqtida javob bermadi. «O'chirish» tugmasini yana bosing — buni takrorlash xavfsiz.";

  /// Maps [AuthController.deleteAccountErrorCode] onto the sentence the user reads.
  ///
  /// The same code-to-string shape the shop and product screens use. An unrecognised code falls
  /// back to the general failure rather than throwing: a new code shipped by a future version of
  /// the controller should read slightly vague, not crash the dialog that reports it.
  String deleteAccountErrorFor(String? code) => switch (code) {
        'timeout' => deleteAccountTimedOut,
        _ => deleteAccountFailed,
      };
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

  // The Basket Price Index, in the only form a customer ever sees it: words. The number itself
  // (96, 104) never leaves the backend - see backend/internal/pricing for why.
  //
  // "рынок" here means "the other shops selling the same basket", which is a narrower claim than it
  // sounds and is the reason the backend withholds the badge entirely until a category has enough
  // shops to have a market at all.
  String priceTierCheaper(int percent) =>
      isRu ? 'на $percent% дешевле рынка' : "bozordan $percent% arzon";
  String get priceTierAverage =>
      isRu ? 'Средняя цена по рынку' : "Bozor o'rtacha narxi";
  String priceTierDearer(int percent) =>
      isRu ? 'на $percent% дороже рынка' : "bozordan $percent% qimmat";

  /// What the whole shared basket costs at this shop, in so'm - the index's own step 1, and the one
  /// absolute price a shop card shows.
  String get basketPrice => isRu ? 'Цена корзины' : 'Savat narxi';
  String get basketPriceShort => isRu ? 'Корзина' : 'Savat';

  // ── the labels on an empty slot ──
  //
  // The VIP carousel is five places whether or not they are sold, and each tab of Лучшие предложения
  // is fifteen. An unsold place draws the real card with **field names where its values would be**,
  // so a shop owner scrolling their own app sees exactly what the space would give them.
  //
  // These are therefore the names of *fields*, not sentences and not marketing: «Адрес», not «Здесь
  // будет адрес магазина». The card already reads as empty from its recessed surface, and a slot
  // that explained itself in prose would be the loudest thing on the home screen.
  //
  // **Nothing here may become a plausible value.** No name, no street, no amount, no percentage - the
  // one section of this app that is sold is the last place a convincing fake belongs. (The rating an
  // empty slot shows is a fixed "5", written where it is drawn rather than here: it is a numeral in
  // both languages.)
  String get slotShopNameLabel => isRu ? 'Название магазина' : "Do'kon nomi";
  String get slotAddressLabel => isRu ? 'Адрес' : 'Manzil';

  /// Deliberately not [basketPriceShort] («Корзина»), which is a caption over a number the reader can
  /// already see. With no number under it the caption has to name the thing on its own, and "средний
  /// чек" is what a shop owner calls it.
  String get slotBasketLabel => isRu ? 'Средний чек' : "O'rtacha chek";

  /// The badge's slot, described rather than shown. It names the comparison the section exists to
  /// make - see [priceTierCheaper], which is what fills this line on a real card.
  String get slotComparisonLabel =>
      isRu ? 'Насколько дешевле рынка' : 'Bozordan qancha arzon';

  /// Shown to a *customer* on the shop's card in place of the price, for a shop that has not priced
  /// its whole catalogue and is therefore out of the comparison entirely (migration 000013).
  ///
  /// Worded as the shop's state rather than the app's: "нет данных" would read as something broken
  /// on our side, and this is a shop that simply has not finished. It says nothing about how much is
  /// left - that is the owner's business, and a customer counting somebody else's unfilled fields is
  /// not information they can act on.
  String get basketPriceIncomplete => isRu
      ? 'Магазин ещё не указал все цены, поэтому сравнения нет'
      : "Do'kon hali barcha narxlarni ko'rsatmagan, shuning uchun taqqoslash yo'q";

  /// The average price of one product inside a single category, shown on the category drill-down.
  /// Deliberately worded differently from [priceIndex]: it is a price in so'm, not a comparison.
  String get categoryAveragePriceShort => isRu ? 'Сред. цена' : "O'rt. narx";

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
  // the category drill-down, opened by tapping a "Популярные категории" tile. it lists products
  // from every shop, so the copy talks about товары rather than магазины.
  // `noShopsYetHint` lived here and is deleted. It was the second line of the home screen's "пока
  // нет магазинов" block, and that block went when both feed sections started drawing their open
  // places - a screen of designed-empty cards followed by a notice explaining that it is empty says
  // the same thing twice. `noShopsYet` itself stays: the map still uses it, where an empty result
  // really does need a sentence, because a map with no pins looks like a map that failed.

  /// `GET /api/home` failed. Its own sentence rather than [noShopsYet], because "nobody has priced
  /// anything yet" and "we could not ask" are opposite claims and only one of them is about Domix.
  String get homeLoadError => isRu
      ? 'Не удалось загрузить главную'
      : "Bosh sahifani yuklab bo'lmadi";

  String get categoryProductsSubtitle =>
      isRu ? 'Товары со всех магазинов' : "Barcha do'konlardagi mahsulotlar";
  String get noProductsInCategory =>
      isRu ? 'Пока нет товаров' : 'Hozircha mahsulotlar yo\'q';
  String get noProductsInCategoryHint => isRu
      ? 'В этой категории ещё никто не указал цены. Загляните позже.'
      : "Bu kategoriyada hali hech kim narx ko'rsatmagan. Keyinroq qarang.";
  String get categoryProductsLoadError =>
      isRu ? 'Не удалось загрузить товары' : "Mahsulotlarni yuklab bo'lmadi";

  // product search, opened from the home screen's field. it lands on the same screen the category
  // tiles open, so it borrows that screen's error and count strings and only needs its own heading
  // and empty state.
  // the heading is the query itself in guillemets, not "Результаты поиска: цемент" - the screen is
  // already obviously a result list, and the one thing worth confirming is what was actually
  // searched for. `searchNoResults` is the map panel's and is reused verbatim: two screens saying
  // "nothing found" differently would be two translations of one sentence.
  String searchResultsTitle(String query) => '«$query»';
  String get searchNoResultsHint => isRu
      ? 'Попробуйте другое название или загляните в категории на главной.'
      : "Boshqa nom bilan urinib ko'ring yoki bosh sahifadagi kategoriyalarga qarang.";

  // the search screen before anything has been searched. it is a real state with a real sentence
  // rather than a blank page: an empty screen under a focused text field reads as a screen that
  // failed to load, and this is the first thing anyone sees after tapping the search bar.
  String get searchPromptTitle => isRu ? 'Что вы ищете?' : 'Nimani qidiryapsiz?';
  String get searchPromptHint => isRu
      ? 'Введите название товара — например «цемент» или «плитка» — и нажмите поиск на клавиатуре.'
      : "Mahsulot nomini kiriting — masalan «sement» yoki «plitka» — va klaviaturadagi qidiruvni bosing.";

  /// Shown once one character has been typed, because at that point the keyboard's search key is
  /// live and pressing it does nothing - the backend refuses a one-character query (it matches a
  /// large share of the catalogue and costs a full scan to return noise). Saying so beats a search
  /// key that silently ignores the press.
  String get searchMinLengthHint => isRu
      ? 'Введите минимум два символа.'
      : "Kamida ikkita belgi kiriting.";

  String get currencySom => isRu ? 'сум' : "so'm";

  // "1250000" -> "1 250 000 сум" (or "so'm"). lives here rather than in one screen because the map
  // pin label, the shop card and the home feed all show the same amount and must agree - a
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
  // the category drill-down, opened by tapping a "Популярные категории" tile

  // the category screen's subtitle counts its shops with the existing shopsCountLabel below - the
  // russian plural rule is already written once in _ruPlural and does not want a second copy.

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

  // the support chat behind the Сообщения tab. it is a conversation with one other party, so the
  // copy says «мы» and not «поддержка Domix ответит» - the second reads like a ticket system, which
  // is exactly the distance this screen exists to remove.
  String get supportChatTitle => isRu ? 'Поддержка' : "Qo'llab-quvvatlash";
  String get supportChatSubtitle =>
      isRu ? 'Отвечаем в рабочее время' : 'Ish vaqtida javob beramiz';

  /// The label under a message we sent. Named, because a bubble with no author reads as a system
  /// notice; «Поддержка Domix» is a person on the other end.
  String get supportSenderLabel => isRu ? 'Поддержка Domix' : "Domix qo'llab-quvvatlash";

  String get supportEmptyTitle => isRu ? 'Напишите нам' : 'Bizga yozing';
  String get supportEmptyBody => isRu
      ? 'Вопрос о магазине, ценах или приложении — задайте его здесь, ответим в этой переписке.'
      : "Do'kon, narxlar yoki ilova haqida savolingizni shu yerda yozing — shu yozishmada javob beramiz.";

  String get supportComposerHint => isRu ? 'Сообщение…' : 'Xabar…';
  String get supportSendLabel => isRu ? 'Отправить' : 'Yuborish';

  // a guest cannot write in, and the reason is worth stating rather than hiding behind a disabled
  // field: the answer has to arrive somewhere, and without an account there is nowhere to put it.
  String get supportGuestTitle =>
      isRu ? 'Войдите, чтобы написать' : 'Yozish uchun hisobga kiring';
  String get supportGuestBody => isRu
      ? 'Ответ придёт в эту переписку, поэтому нужен аккаунт — вход занимает полминуты через Telegram.'
      : "Javob shu yozishmaga keladi, shuning uchun hisob kerak — Telegram orqali kirish yarim daqiqa oladi.";
  String get supportGuestAction => isRu ? 'Войти' : 'Kirish';

  String get supportLoadError =>
      isRu ? 'Не удалось загрузить переписку' : "Yozishmani yuklab bo'lmadi";
  String get supportLoadErrorHint => isRu
      ? 'Проверьте подключение и попробуйте снова.'
      : "Ulanishni tekshirib, qayta urinib ko'ring.";

  /// Localizes a failed send off the backend's stable `code` (see SupportException).
  String supportSendErrorMessage(String code) {
    switch (code) {
      case 'empty_message':
        return isRu ? 'Сообщение пустое.' : "Xabar bo'sh.";
      case 'message_too_long':
        return isRu
            ? 'Сообщение слишком длинное — сократите его.'
            : "Xabar juda uzun — qisqartiring.";
      // the flood guard. it is a wait and not a refusal, and the words have to say so or it reads
      // as "you have been blocked".
      case 'too_many_messages':
        return isRu
            ? 'Слишком много сообщений подряд. Подождите минуту.'
            : "Ketma-ket juda ko'p xabar. Bir daqiqa kuting.";
      case 'timeout':
        return isRu
            ? 'Сервер не ответил. Нажмите «Отправить» ещё раз.'
            : "Server javob bermadi. «Yuborish»ni yana bosing.";
      case 'unauthorized':
        return isRu ? 'Войдите, чтобы отправить сообщение.' : 'Xabar yuborish uchun hisobga kiring.';
      default:
        return isRu
            ? 'Не удалось отправить. Проверьте подключение.'
            : "Yuborib bo'lmadi. Ulanishni tekshiring.";
    }
  }

  // day separators in the chat. anything older than yesterday gets its date, which is the point at
  // which "вчера" stops being information.
  String get todayLabel => isRu ? 'Сегодня' : 'Bugun';
  String get yesterdayLabel => isRu ? 'Вчера' : 'Kecha';

  // placeholder screens. these read as a title plus a line of "what will appear here", the shape
  // EmptyStateView wants.
  String get ticketsComingSoonTitle =>
      isRu ? 'Заявки мастерам' : 'Ustalarga buyurtmalar';
  String get ticketsComingSoonBody => isRu
      ? 'Скоро здесь можно будет оставить заявку на работу, а мастера и бригады будут откликаться на неё.'
      : "Tez orada bu yerda ish uchun buyurtma qoldirasiz, ustalar va brigadalar unga javob beradi.";
  String get comingSoonBadge => isRu ? 'Скоро' : 'Tez orada';

  // map screen (shop pins)
  String get noShopsYet => isRu ? 'Пока нет магазинов' : "Hozircha do'konlar yo'q";

  /// Shown over the map while it is zoomed too far out to draw pins. Carries the count, because the
  /// whole job of this line is to say there *is* something to zoom into - without it, an empty map
  /// and a city with no shops look identical.
  String zoomInForShops(int count) => isRu
      ? 'Приблизьте карту · ${shopsCountLabel(count)}'
      : "Xaritani yaqinlashtiring · ${shopsCountLabel(count)}";
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

  // the shop card's contacts block. the phone number is shown as a labelled detail row, so the call
  // button carries a short verb instead of the raw number - a cta reads better as an action than as
  // data.
  String get addressLabel => isRu ? 'Адрес' : 'Manzil';
  String get phoneLabel => isRu ? 'Телефон' : 'Telefon';
  String get callButton => isRu ? 'Позвонить' : "Qo'ng'iroq qilish";

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
  // the code behind this stays 'wood' - renaming a stored value is a data migration, and this is a
  // display change. "Дерево" named the material; a shop sells материалы out of it.
  String get shopCategoryWood => isRu ? 'Древесные материалы' : "Yog'och materiallar";
  String get shopCategoryWallpaper => isRu ? 'Обои' : 'Oboylar';

  String get shopCategoryUniversalHint => isRu
      ? 'Всё для стройки: смеси, блоки, крепёж, электрика'
      : "Qurilish uchun hammasi: aralashmalar, bloklar, mahkamlagichlar, elektrika";
  String get shopCategoryPlumbingHint => isRu
      ? 'Трубы, фитинги, смесители, отопление'
      : "Quvurlar, fitinglar, smesitellar, isitish";
  String get shopCategoryWoodHint => isRu
      ? 'Пиломатериалы, фанера, вагонка, ДСП'
      : "Xodalar, faner, vagonka, DSP";
  // обои are the one category whose catalogue is places rather than products, and the owner has to
  // know that before they pick it - not afterwards, when the category can no longer be changed
  String get shopCategoryWallpaperHint => isRu
      ? '10 мест под ваши обои: премиум, стандарт, эконом'
      : "Oboylaringiz uchun 10 ta joy: premium, standart, ekonom";

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
      // the request went out and nothing came back in time. almost always transient, and the right
      // advice is "press save again" - which is why it cannot share the default's wording, since
      // that one tells the owner to go and check a connection that is working.
      case 'timeout':
        return isRu
            ? 'Сервер не ответил вовремя. Нажмите «Сохранить» ещё раз.'
            : "Server javob bermadi. «Saqlash»ni yana bosing.";
      // the server answered, and with something we did not plan for. saying so is worth more than
      // guessing at a cause: it is not the phone's network, and the owner retrying forever will not
      // help. the underlying exception goes to the log - see ProductsController._mutate.
      case 'server_error':
        return isRu
            ? 'Ошибка на сервере. Попробуйте позже.'
            : "Serverda xatolik. Keyinroq urinib ko'ring.";
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

  /// "Цены указаны: 12 из 50" - the progress line at the top of the owner's grid. counts the
  /// category template only, because that is the count with a consequence attached (see below).
  String pricedProgressLabel(int priced, int total) => isRu
      ? 'Цены указаны: $priced из $total'
      : "Narxlar ko'rsatilgan: $total dan $priced";

  /// What finishing the template actually buys, said in the one place the owner can act on it.
  ///
  /// Since migration 000013 a shop joins the price comparison only once every template product has a
  /// price - one missing row keeps it out of Лучшие предложения, off the badges and out of every
  /// other shop's market average. That rule is invisible from anywhere else in the app: the owner
  /// would simply never see a badge and have nothing to connect it to.
  ///
  /// Two strings rather than one conditional sentence, because the completed state is not a weaker
  /// version of the warning - it is a different message, and the only positive confirmation the
  /// owner ever gets that the work was worth doing.
  String priceIndexNeedsEveryPrice(int remaining) => isRu
      ? 'Осталось $remaining — магазин попадёт в сравнение цен, когда указаны все'
      : "$remaining ta qoldi - barchasi ko'rsatilganda do'kon narx taqqoslashiga qo'shiladi";
  String get priceIndexParticipating => isRu
      ? 'Магазин участвует в сравнении цен'
      : "Do'kon narx taqqoslashida ishtirok etmoqda";

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

  /// the обои case: a template row whose product the owner supplies. it explains a *different*
  /// rule from the one above - the name is theirs to write - so it is a separate string rather
  /// than a paragraph appended to that one.
  String get slotProductHint => isRu
      ? 'Место под ваши обои. Класс и страну менять нельзя — по ним ваш магазин сравнивается с другими. Впишите свою коллекцию, цену за рулон и наличие. Удалить это место нельзя.'
      : "Sizning oboylaringiz uchun joy. Sinf va davlatni o'zgartirib bo'lmaydi — do'koningiz shular bo'yicha boshqalar bilan taqqoslanadi. O'z kolleksiyangizni, rulon narxini va mavjudligini kiriting. Bu joyni o'chirib bo'lmaydi.";

  /// placeholder in the name field of a слот, where the label alone would say nothing useful
  String get slotProductNameHint => isRu
      ? 'Например: Erismann Vlies 1,06 м'
      : "Masalan: Erismann Vlies 1,06 m";

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

  /// The filter over one shop's own catalogue. Names what it searches - a Универсальный shop is a
  /// hundred tiles, and «Поиск» alone on a screen that already has a search bar elsewhere would not
  /// say which of the two this one is.
  String get shopProductsSearchHint =>
      isRu ? 'Поиск по товарам магазина' : "Do'kon mahsulotlari bo'yicha qidirish";

  // product add/edit/delete failures - keyed off the backend's machine-readable `code` (see
  // writeAPIError in backend/internal/endpoints/authz.go), same contract as the two above
  String productErrorMessage(String code, {int? limit}) {
    switch (code) {
      case 'product_limit_reached':
        final max = limit ?? 30;
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
      // the request went out and nothing came back in time. almost always transient, and the right
      // advice is "press save again" - which is why it cannot share the default's wording, since
      // that one tells the owner to go and check a connection that is working.
      case 'timeout':
        return isRu
            ? 'Сервер не ответил вовремя. Нажмите «Сохранить» ещё раз.'
            : "Server javob bermadi. «Saqlash»ni yana bosing.";
      // the server answered, and with something we did not plan for. saying so is worth more than
      // guessing at a cause: it is not the phone's network, and the owner retrying forever will not
      // help. the underlying exception goes to the log - see ProductsController._mutate.
      case 'server_error':
        return isRu
            ? 'Ошибка на сервере. Попробуйте позже.'
            : "Serverda xatolik. Keyinroq urinib ko'ring.";
      default:
        return isRu
            ? 'Не удалось сохранить. Проверьте подключение и попробуйте снова.'
            : "Saqlab bo'lmadi. Ulanishni tekshirib, qayta urinib ko'ring.";
    }
  }

  // ── the shop card ────────────────────────────────────────────────────────────────────────────
  //
  // One screen, reached from the map's pins, the VIP carousel and Лучшие предложения - see
  // ShopCardScreen. These are the labels that exist only there; the address, phone, basket and
  // product strings above are shared with the rest of the app.

  String get shopContactsTitle => isRu ? 'Контакты' : 'Kontaktlar';

  /// Opens the phone's own maps app with a route to the shop. Named for the result rather than for
  /// the mechanism ("открыть в Яндекс.Картах"), because which app answers depends on the phone.
  String get routeButton => isRu ? 'Маршрут' : "Yo'nalish";

  /// The paid placement, as a badge on the card. Not translated - it is the same three letters in
  /// both languages and in the section heading above.
  String get vipBadge => 'VIP';

  /// url_launcher came back false: nothing on the phone would take the tel: or the maps link. The
  /// number is on screen either way, which is what makes this a message rather than a failure.
  String get couldNotOpenExternalApp => isRu
      ? 'Не удалось открыть приложение на телефоне'
      : "Telefondagi ilovani ochib bo'lmadi";

  // ── the product photo an owner uploads ───────────────────────────────────────────────────────
  //
  // Every product in the owner's own shop can carry one, template rows included: what makes two
  // shops comparable is the row's key, name and unit, none of which a photo touches. See
  // backend/internal/endpoints/product_image.go.

  String get productPhotoLabel => isRu ? 'Фото товара' : 'Mahsulot rasmi';

  /// Says what the photo is *for*, which is the only thing that makes an optional field worth
  /// filling in. Deliberately one sentence, and true of every product: a template row whose photo
  /// is the catalogue's, an обои slot that has none, and the owner's own.
  String get productPhotoHint => isRu
      ? 'Покупатели видят это фото в каталоге магазина.'
      : "Xaridorlar bu rasmni do'kon katalogida ko'radi.";

  /// Why the picture on a seeded row is not a control.
  ///
  /// Worded as what the photo *is* rather than as what the owner may not do: the rule is that this
  /// picture is the same in every shop of the category, and once that is said the restriction
  /// explains itself. «Вы не можете изменить фото» would be the same sentence with an accusation in
  /// it, over a photo they have done nothing to.
  String get cataloguePhotoNote => isRu
      ? 'Это фото из общего каталога — оно одинаковое во всех магазинах вашей категории, поэтому его нельзя заменить. Свои фото можно ставить на товары, которые вы добавили сами.'
      : "Bu umumiy katalogdagi rasm — u sizning kategoriyangizdagi barcha do'konlarda bir xil, shuning uchun uni almashtirib bo'lmaydi. O'z rasmlaringizni o'zingiz qo'shgan mahsulotlarga qo'ya olasiz.";

  String get addPhotoAction => isRu ? 'Добавить фото' : "Rasm qo'shish";
  String get changePhotoAction => isRu ? 'Заменить' : "Almashtirish";
  String get removePhotoAction => isRu ? 'Удалить фото' : "Rasmni o'chirish";

  String get photoSourceTitle => isRu ? 'Откуда взять фото' : 'Rasmni qayerdan olamiz';
  String get photoFromCamera => isRu ? 'Сделать снимок' : 'Suratga olish';
  String get photoFromGallery => isRu ? 'Выбрать из галереи' : 'Galereyadan tanlash';

  String get photoUploadingLabel => isRu ? 'Загружаем фото…' : 'Rasm yuklanmoqda…';
  String get photoSavedMessage => isRu ? 'Фото сохранено' : 'Rasm saqlandi';
  String get photoRemovedMessage => isRu ? 'Фото удалено' : "Rasm o'chirildi";

  /// On a product being created there is no id to attach a photo to yet, so the picked file waits
  /// on the phone until the product exists. Saying so is what stops the delay reading as a failure.
  String get photoPendingSaveLabel => isRu
      ? 'Загрузится после сохранения товара'
      : 'Mahsulot saqlangach yuklanadi';

  /// The honest report of a half-success: the product was created and the photo was not. Two
  /// requests, so it is a state that genuinely exists - and the product is already saved, which is
  /// why this is a message rather than an error the owner is asked to fix on the spot.
  String get productSavedWithoutPhoto => isRu
      ? 'Товар сохранён, но фото не загрузилось. Откройте товар и добавьте фото ещё раз.'
      : "Mahsulot saqlandi, lekin rasm yuklanmadi. Mahsulotni ochib, rasmni qayta qo'shing.";

  /// Photo failures, keyed off the backend's machine-readable `code` - the same contract as
  /// [productErrorMessage]. Separate from it because every message here is about a *file* and the
  /// advice that goes with each one is different: a photo that is not a photo is not fixed by
  /// pressing save again.
  String photoErrorMessage(String code) {
    switch (code) {
      case 'invalid_image':
        return isRu
            ? 'Это не похоже на фото. Подойдут JPG и PNG.'
            : "Bu rasmga o'xshamaydi. JPG va PNG mos keladi.";
      case 'image_too_large':
        return isRu
            ? 'Фото слишком большое. Выберите файл поменьше.'
            : 'Rasm juda katta. Kichikroq faylni tanlang.';
      case 'image_too_small':
        return isRu
            ? 'Фото слишком маленькое — оно будет размытым в каталоге.'
            : "Rasm juda kichik — katalogda xira ko'rinadi.";
      case 'too_many_uploads':
        return isRu
            ? 'Слишком много фото подряд. Подождите немного.'
            : "Ketma-ket juda ko'p rasm. Biroz kuting.";
      // the screen hides the control on a locked row, so this only ever arrives on an app that is a
      // build behind the rule - or one talking to a backend where a catalogue was photographed
      // between opening the form and pressing the button. it says the rule rather than "forbidden".
      case 'template_photo':
        return isRu
            ? 'Фото товара из общего каталога изменить нельзя.'
            : "Umumiy katalogdagi mahsulot rasmini o'zgartirib bo'lmaydi.";
      // the picker itself refused - no camera on the device, or the owner declined access. it never
      // reaches the network, so it has no server code and gets one of its own.
      case 'picker_failed':
        return isRu
            ? 'Не удалось открыть камеру или галерею.'
            : "Kamera yoki galereyani ochib bo'lmadi.";
      case 'not_owner':
      case 'forbidden_role':
        return isRu
            ? 'У вас нет прав на изменение товаров этого магазина.'
            : "Bu do'kon mahsulotlarini o'zgartirish huquqingiz yo'q.";
      case 'product_not_found':
        return isRu
            ? 'Товар не найден — возможно, он уже удалён.'
            : "Mahsulot topilmadi — ehtimol u allaqachon o'chirilgan.";
      case 'unauthorized':
        return isRu
            ? 'Сессия истекла. Войдите в аккаунт заново.'
            : 'Seans tugadi. Hisobingizga qayta kiring.';
      // an upload is the one request in the app big enough to time out on a working connection, so
      // "try again" is genuinely the right advice here rather than a shrug
      case 'timeout':
        return isRu
            ? 'Фото не успело загрузиться. Попробуйте ещё раз.'
            : "Rasm yuklanib ulgurmadi. Qayta urinib ko'ring.";
      case 'server_error':
        return isRu
            ? 'Ошибка на сервере. Попробуйте позже.'
            : "Serverda xatolik. Keyinroq urinib ko'ring.";
      default:
        return isRu
            ? 'Не удалось загрузить фото. Проверьте подключение.'
            : "Rasmni yuklab bo'lmadi. Ulanishni tekshiring.";
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
