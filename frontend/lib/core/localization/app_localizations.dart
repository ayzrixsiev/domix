import 'package:flutter/material.dart';

import 'package:frontend/core/network/api_client.dart';

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

  String get vendorBadge => isRu ? 'Продавец' : 'Sotuvchi';
  String get manageShops =>
      isRu ? 'Управление магазинами' : "Do'konlarni boshqarish";
  String get shopSettings =>
      isRu ? 'Настройка магазинов' : "Do'konlar sozlamalari";
  String get addStore =>
      isRu ? 'Добавить новый магазин' : "Yangi do'kon qo'shish";
  String get backButton => isRu ? 'Назад в профиль' : 'Profilga qaytish';

  // deliberately not "back": the group expands in place, so nothing is being navigated away from
  String get closeButton => isRu ? 'Закрыть' : 'Yopish';
  String get favorites => isRu ? 'Избранное' : 'Tanlanganlar';
  String get favoritesEmptyTitle =>
      isRu ? 'Здесь пока пусто' : "Bu yerda hozircha bo'sh";
  String get favoritesEmptyBody => isRu
      ? 'Нажмите сердечко на товаре, и он появится здесь.'
      : "Mahsulotdagi yurakchani bosing va u shu yerda paydo bo'ladi.";
  String get favoritesLoadError => isRu
      ? 'Не удалось загрузить избранное'
      : "Tanlanganlarni yuklab bo'lmadi";
  String get languageSettings => isRu ? 'Язык приложения' : 'Ilova tili';
  String get logout => isRu ? 'Выйти из аккаунта' : 'Akkauntdan chiqish';

  // google play requires in-app deletion, and the dialog has to name what disappears
  String get deleteAccount => isRu ? 'Удалить аккаунт' : "Akkauntni o'chirish";
  String get deleteAccountConfirmTitle =>
      isRu ? 'Удалить аккаунт?' : "Akkaunt o'chirilsinmi?";
  String get deleteAccountConfirmBody => isRu
      ? 'Ваш профиль, все ваши магазины и все их товары будут удалены безвозвратно. '
            'Это действие нельзя отменить.'
      : "Profilingiz, barcha do'konlaringiz va ulardagi barcha mahsulotlar butunlay o'chiriladi. "
            "Bu amalni bekor qilib bo'lmaydi.";
  String get deleteAccountConfirmAction => isRu ? 'Удалить' : "O'chirish";

  /// Its own headline rather than [errorDialogTitle], which is paired with Telegram instructions.
  String get deleteAccountFailedTitle =>
      isRu ? 'Не удалось удалить аккаунт' : "Akkauntni o'chirib bo'lmadi";
  String get deleteAccountFailed => isRu
      ? 'Не удалось удалить аккаунт. Проверьте соединение и попробуйте ещё раз.'
      : "Akkauntni o'chirib bo'lmadi. Aloqani tekshiring va qayta urinib ko'ring.";

  // the request most likely did reach the server, so the advice is "press it again" - which is safe
  String get deleteAccountTimedOut => isRu
      ? 'Сервер не ответил вовремя. Нажмите «Удалить» ещё раз — повторное нажатие безопасно.'
      : "Server o'z vaqtida javob bermadi. «O'chirish» tugmasini yana bosing — buni takrorlash xavfsiz.";

  /// An unrecognised code falls back to the general failure rather than throwing.
  String deleteAccountErrorFor(String? code) => switch (code) {
    'timeout' => deleteAccountTimedOut,
    _ => deleteAccountFailed,
  };
  String get selectLanguage => isRu ? 'Выберите язык' : 'Tilni tanlang';
  String get version => 'Domix • 1.0.0';

  // ---------------------------------------------------------------------------------------------
  // Onboarding: the four steps a guest walks through before an account exists.
  // ---------------------------------------------------------------------------------------------

  /// The header over the whole flow, so the guest tab is a titled screen rather than a card on an
  /// empty canvas - see ScreenHeader.
  String get onboardingTitle => isRu ? 'Вход в Domix' : "Domix'ga kirish";
  String get onboardingSubtitle =>
      isRu ? 'Несколько коротких шагов' : "Bir necha qisqa qadam";

  /// «Шаг 2 из 4», read aloud by the progress bar and shown beside it.
  String stepCounter(int step, int total) =>
      isRu ? 'Шаг $step из $total' : "$total qadamdan $step-si";

  String get nextButton => isRu ? 'Далее' : 'Keyingisi';

  /// Not [backButton], which is «Назад в профиль» and names a destination - this one only walks one
  /// step back inside the flow.
  String get stepBackButton => isRu ? 'Назад' : 'Orqaga';

  // step 2 - privacy policy
  String get onboardingPolicyTitle =>
      isRu ? 'Политика конфиденциальности' : 'Maxfiylik siyosati';
  String policyRevision(String date) =>
      isRu ? 'Редакция от $date' : '$date tahriri';
  String get policyReadFull => isRu ? 'Читать полностью' : "To'liq o'qish";
  String get policyAcceptLabel => isRu
      ? 'Я прочитал(а) и принимаю политику конфиденциальности'
      : "Men maxfiylik siyosatini o'qidim va qabul qilaman";

  /// Shown when «Далее» is pressed with the box unticked, instead of a disabled button that never
  /// explains itself.
  String get policyMustAccept => isRu
      ? 'Чтобы продолжить, примите политику конфиденциальности'
      : "Davom etish uchun maxfiylik siyosatini qabul qiling";

  // step 4 - telegram
  String get telegramStepBody => isRu
      ? 'Откроется наш бот в Telegram. Нажмите там «Поделиться номером» — и вы вернётесь в Domix уже со входом.'
      : "Telegram'da botimiz ochiladi. U yerda «Raqamni ulashish» tugmasini bosing — Domix'ga kirgan holda qaytasiz.";
  String get telegramSignInButton => isRu
      ? 'Зарегистрироваться через Telegram'
      : "Telegram orqali ro'yxatdan o'tish";
  String get telegramWaitingTitle =>
      isRu ? 'Ждём номер из Telegram' : "Telegram'dan raqamni kutyapmiz";
  String get telegramWaitingBody => isRu
      ? 'Нажмите в боте «Поделиться номером». Этот экран обновится сам.'
      : "Botda «Raqamni ulashish» tugmasini bosing. Bu ekran o'zi yangilanadi.";
  String get telegramReopenButton =>
      isRu ? 'Открыть Telegram снова' : "Telegram'ni qayta ochish";

  /// Every refusal the sign-in can end in, as written copy: the api's error `code` on a refused
  /// request, or the poll's `status` on a finished one. **A code, not the server's sentence**: the
  /// server speaks one language and the app the reader's, and an unknown one has to land somewhere.
  String authErrorFor(String? code) => switch (code) {
    'name_too_long' => nameTooLongError,
    'rate_limited' || 'busy' => authTooManyRequests,
    'expired' => authSessionExpired,
    'not_uzbek' => authNotUzbek,
    'telegram_not_opened' => authTelegramNotOpened,
    _ => authGenericError,
  };

  String get nameTooLongError => isRu ? 'Имя слишком длинное' : 'Ism juda uzun';
  String get authTooManyRequests => isRu
      ? 'Слишком много запросов. Подождите немного.'
      : "So'rovlar juda ko'p. Biroz kuting.";
  String get authSessionExpired => isRu
      ? 'Время вышло: номер не подтвердили за 10 минут. Попробуйте ещё раз.'
      : "Vaqt tugadi: raqam 10 daqiqa ichida tasdiqlanmadi. Qayta urinib ko'ring.";
  String get authNotUzbek => isRu
      ? 'Domix работает только с узбекскими номерами (+998).'
      : "Domix faqat O'zbekiston raqamlari (+998) bilan ishlaydi.";
  String get authTelegramNotOpened => isRu
      ? 'Не удалось открыть Telegram. Попробуйте ещё раз.'
      : "Telegram'ni ochib bo'lmadi. Qayta urinib ko'ring.";
  String get authGenericError => isRu
      ? 'Что-то пошло не так. Попробуйте ещё раз.'
      : "Nimadir xato ketdi. Qayta urinib ko'ring.";

  /// Every refusal PATCH /api/me can answer with. Falls through to [authErrorFor].
  String profileErrorFor(String? code) => switch (code) {
    'name_required' => nameRequiredError,
    'role_locked' => roleLockedNote,
    'account_deleted' => sessionExpiredBody,
    _ => authErrorFor(code),
  };

  // ── the profile, signed out ──
  String get profileGuestTitle => isRu ? 'Войдите в аккаунт' : 'Hisobga kiring';
  String get profileGuestBody => isRu
      ? 'Аккаунт нужен, чтобы сохранять товары, писать магазинам и открыть свой.'
      : "Mahsulotlarni saqlash, do'konlarga yozish va o'zingiznikini ochish uchun hisob kerak.";
  String get profileGuestAction => isRu ? 'Войти' : 'Kirish';
  String get onboardingNoAccount => isRu
      ? 'Аккаунта ещё нет? Он создастся сам — просто войдите через Telegram.'
      : "Hisobingiz yo'qmi? U o'zi yaratiladi — shunchaki Telegram orqali kiring.";

  // ── editing the profile ──
  String get editProfileTitle => isRu ? 'Профиль' : 'Profil';
  String get editProfileSubtitle =>
      isRu ? 'Имя и роль аккаунта' : 'Hisob ismi va roli';

  String get editProfileButton => isRu ? 'Изменить' : "O'zgartirish";
  String get accountSavedMessage =>
      isRu ? 'Профиль сохранён' : 'Profil saqlandi';

  /// The rule the server enforces too (PATCH /api/me answers `role_locked`): a role goes one way.
  String get roleLockedNote => isRu
      ? 'Роль аккаунта изменить нельзя.'
      : "Hisob rolini o'zgartirib bo'lmaydi.";
  String get roleChangeWarning => isRu
      ? 'Роль выбирается один раз — поменять её потом не получится.'
      : "Rol bir marta tanlanadi — keyin uni o'zgartirib bo'lmaydi.";
  String get roleChangeConfirmTitle =>
      isRu ? 'Сменить роль?' : "Rol o'zgartirilsinmi?";
  String roleChangeConfirmBody(String role) => isRu
      ? 'Аккаунт станет «$role». Вернуть прежнюю роль будет нельзя.'
      : "Hisob «$role» bo'ladi. Avvalgi rolni qaytarib bo'lmaydi.";
  String get roleChangeConfirmAction => isRu ? 'Сменить' : "O'zgartirish";

  String get nameInputLabel => isRu ? 'Имя и фамилия' : "Ism va familiyangiz";
  String get nameRequiredError =>
      isRu ? 'Пожалуйста, введите имя' : "Iltimos, ismingizni kiriting";

  /// three stacked rows need a question above them or the list reads as settings
  String get registerRolePrompt => isRu ? 'Кто вы?' : 'Siz kimsiz?';

  // the picker is a stacked list, so each option has the full width to say what it gets you
  String get roleCustomer => isRu ? 'Покупатель' : "Xaridor";
  String get roleCustomerSub => isRu
      ? 'Покупаю материалы и ищу мастеров'
      : "Material sotib olaman va usta qidiraman";
  String get roleVendor => isRu ? 'Владелец магазина' : "Do'kon egasi";
  String get roleVendorSub => isRu
      ? 'Мой магазин, товары и цены'
      : "Mening do'konim, mahsulot va narxlar";

  String get cancelButton => isRu ? 'Отменить' : 'Bekor qilish';

  // error dialog shown when the login attempt fails
  String get errorDialogTitle =>
      isRu ? 'Что-то пошло не так' : 'Nimadir xato ketdi';
  String get okButton => isRu ? 'Понятно' : 'Tushunarli';

  // shown when a request the user made came back 401 - see SessionExpiryGuard
  String get sessionExpiredTitle =>
      isRu ? 'Сессия истекла' : 'Sessiya muddati tugadi';
  String get sessionExpiredBody => isRu
      ? 'Срок вашей сессии истёк. Пожалуйста, войдите в аккаунт заново.'
      : "Sessiyangiz muddati tugadi. Iltimos, hisobingizga qaytadan kiring.";

  // bottom navigation labels
  String get homeTab => isRu ? 'Главная' : 'Asosiy';
  String get cartTab => isRu ? 'Корзина' : 'Savat';
  String get mapTab => isRu ? 'Карта' : 'Xarita';
  String get messagesTab => isRu ? 'Сообщения' : 'Xabarlar';
  String get profileTab => isRu ? 'Профиль' : 'Profil';

  // the hint names what is actually searched - a placeholder is the only instruction an empty field gets
  String get searchHint =>
      isRu ? 'Ищите товары...' : 'Mahsulotlarni qidiring...';

  /// ranked by lowest average check, not by distance - the copy promises a price, not a location
  String get bestOffersTitle =>
      isRu ? 'Лучшие предложения' : 'Eng yaxshi takliflar';
  String get popularCategories =>
      isRu ? 'Популярные категории' : 'Mashhur kategoriyalar';

  // "VIP" stays latin in both languages: it is the name of the paid tier, not a word to translate
  String get vipShops => isRu ? 'VIP Магазины' : "VIP Do'konlar";

  // the Basket Price Index in the only form a customer sees: words. the number never leaves the
  // backend - see backend/internal/pricing.
  String priceTierCheaper(int percent) =>
      isRu ? 'на $percent% дешевле рынка' : "bozordan $percent% arzon";
  String get priceTierAverage =>
      isRu ? 'Средняя цена по рынку' : "Bozor o'rtacha narxi";
  String priceTierDearer(int percent) =>
      isRu ? 'на $percent% дороже рынка' : "bozordan $percent% qimmat";

  /// what the whole shared basket costs at this shop - the one absolute price a shop card shows
  String get basketPrice => isRu ? 'Цена корзины' : 'Savat narxi';
  String get basketPriceShort => isRu ? 'Корзина' : 'Savat';

  // ── the labels on an empty slot: names of *fields*, not sentences («Адрес», not «Здесь будет
  // адрес магазина»). **nothing here may become a plausible value** - no name, street, amount or
  // percentage, since the one section of the app that is sold is the last place a fake belongs. ──
  String get slotShopNameLabel => isRu ? 'Название магазина' : "Do'kon nomi";
  String get slotAddressLabel => isRu ? 'Адрес' : 'Manzil';

  // with no number under it, the caption has to name the thing on its own
  String get slotBasketLabel => isRu ? 'Средний чек' : "O'rtacha chek";

  // the two captions under the figures on a VIP card. the word is the unit, so it never agrees with
  // the number above it - «1 Товаров» is not drawn, the caption is a column heading.
  String get cardRatingCaption => isRu ? 'Рейтинг' : 'Reyting';
  String get cardProductsCaption => isRu ? 'Товаров' : 'Mahsulot';

  /// **a figure this build has no source for**, drawn where the number goes. the rating is the
  /// standing case: there is no reviews table, so a real shop has nothing to show and an invented
  /// 4.8 over a real shop's name is the one thing the section that is sold cannot carry.
  String get noFigure => '—';

  // «VIP» stays latin - it is the name of the paid tier, not a word - and the noun beside it is
  // what tells a customer the card is an advert rather than the cheapest shop they searched for
  String get vipShopTag => isRu ? 'VIP магазин' : "VIP do'kon";

  /// the badge's slot, described rather than shown - see [priceTierCheaper], which fills this line
  String get slotComparisonLabel =>
      isRu ? 'Насколько дешевле рынка' : 'Bozordan qancha arzon';

  // `basketPriceIncomplete` is deleted: the shop card draws no price section for a shop that has not
  // finished pricing, and saying nothing is the accurate thing to say

  /// a price in so'm, not a comparison - deliberately worded differently from [priceIndex]

  // the twelve product categories, shared by the home grid and the product form. they live here
  // rather than in the database because the stored value is a code: when display names were the
  // stored values, uzbek left every category untranslated.
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

  // the groups a shop's grid is split by, named on the sheet the «Категории» button opens
  String get sectionAll => isRu ? 'Все товары' : 'Barcha mahsulotlar';
  String get sectionsButton => isRu ? 'Категории' : 'Turkumlar';
  String get sectionFullTapesAbrasives => isRu
      ? 'Ленты, расходники, абразивы и диски'
      : 'Lentalar, sarf materiallari, abrazivlar va disklar';
  String get sectionFullDrillsHandTools =>
      isRu ? 'Свёрла и ручной инструмент' : "Parmalar va qo'l asboblari";
  String get sectionFullElectricalLighting =>
      isRu ? 'Электрика и освещение' : 'Elektrika va yoritish';
  String get sectionFullFastenersMounting =>
      isRu ? 'Крепёж и монтаж' : 'Mahkamlagichlar va montaj';
  String get sectionFullMixesPaints => isRu
      ? 'Смеси, клеи, краски и химия'
      : "Qorishmalar, yelimlar, bo'yoqlar va kimyo";
  String get sectionFullFilmsSheets => isRu
      ? 'Плёнки, изоляция и листовые материалы'
      : 'Plyonkalar, izolyatsiya va list materiallari';
  String get sectionFullPipesInsulation =>
      isRu ? 'Трубы и теплоизоляция' : 'Quvurlar va issiqlik izolyatsiyasi';
  String get sectionFullPprFittings =>
      isRu ? 'PPR-фитинги VERO' : 'PPR fitinglari VERO';
  String get sectionFullValvesVero =>
      isRu ? 'Краны и вентили VERO' : 'VERO kranlari va ventillari';
  String get sectionFullSewer =>
      isRu ? 'Канализация VERO' : 'VERO kanalizatsiya';
  String get sectionFullThreadedFittings =>
      isRu ? 'Металлические резьбовые фитинги' : 'Rezbali metall fitinglar';
  String get sectionFullKtmFittings => isRu ? 'Фитинги KTM' : 'KTM fitinglari';
  String get sectionFullValvesKas => isRu ? 'Краны KAS' : 'KAS kranlari';
  String get sectionFullCisternToilet =>
      isRu ? 'Бачок и унитаз' : 'Bachok va unitaz';
  String get sectionFullSiphons => isRu ? 'Сифоны' : 'Sifonlar';
  String get sectionFullDrains => isRu ? 'Трапы' : 'Traplar';
  String get sectionFullWashingMachine =>
      isRu ? 'Для стиральной машины' : 'Kir yuvish mashinasi uchun';
  String get sectionFullFiltersCartridges =>
      isRu ? 'Фильтры и картриджи' : 'Filtrlar va kartridjlar';
  String get sectionFullMixerParts =>
      isRu ? 'Комплектующие для смесителей' : 'Smesitel butlovchi qismlari';
  String get sectionFullHoses =>
      isRu ? 'Гибкие подводки и шланги' : 'Egiluvchan ulagichlar va shlanglar';
  String get sectionFullMixers => isRu ? 'Смесители' : 'Smesitellar';
  // the category drill-down, opened from a "Популярные категории" tile - it lists products

  /// its own sentence rather than [noShopsYet]: "nobody has priced anything" and "we could not ask"
  /// are opposite claims
  String get homeLoadError =>
      isRu ? 'Не удалось загрузить главную' : "Bosh sahifani yuklab bo'lmadi";

  String get categoryProductsSubtitle =>
      isRu ? 'Товары со всех магазинов' : "Barcha do'konlardagi mahsulotlar";
  String get noProductsInCategory =>
      isRu ? 'Пока нет товаров' : 'Hozircha mahsulotlar yo\'q';
  String get noProductsInCategoryHint => isRu
      ? 'В этой категории ещё никто не указал цены. Загляните позже.'
      : "Bu kategoriyada hali hech kim narx ko'rsatmagan. Keyinroq qarang.";
  String get categoryProductsLoadError =>
      isRu ? 'Не удалось загрузить товары' : "Mahsulotlarni yuklab bo'lmadi";

  // two outcomes worth telling apart: the request failed (retry), or the shop is gone (nothing to retry)
  String get shopLoadError =>
      isRu ? 'Не удалось открыть магазин' : "Do'konni ochib bo'lmadi";
  String get shopGoneTitle =>
      isRu ? 'Магазин недоступен' : "Do'kon mavjud emas";
  String get shopGoneBody => isRu
      ? 'Похоже, магазин был удалён. Попробуйте найти другой товар.'
      : "Do'kon o'chirilganga o'xshaydi. Boshqa mahsulotni qidiring.";

  // product search borrows the category screen's error and count strings. the heading is the query
  // itself in guillemets - the one thing worth confirming is what was searched for.
  String get searchNoResultsHint => isRu
      ? 'Попробуйте другое название или загляните в категории на главной.'
      : "Boshqa nom bilan urinib ko'ring yoki bosh sahifadagi kategoriyalarga qarang.";

  // an empty screen under a focused text field reads as one that failed to load
  String get searchPromptTitle =>
      isRu ? 'Что вы ищете?' : 'Nimani qidiryapsiz?';
  // **the examples have to be things the catalogue holds**: it used to suggest «цемент» and «плитка»,
  // neither of which is in it, so a first search taken straight from the hint found nothing. names are
  // Russian and in Cyrillic, which is why the Uzbek line asks for the name as the catalogue writes it -
  // a Latin «sement» can never match.
  String get searchPromptHint => isRu
      ? 'Введите название товара — например «кабель» или «саморезы» — и нажмите поиск на клавиатуре.'
      : "Mahsulot nomini katalogdagidek, rus tilida kiriting — masalan «кабель» yoki «саморезы» — va klaviaturadagi qidiruvni bosing.";

  // the backend refuses a query with no word of three letters, so saying so beats a search key that
  // ignores the press
  String get searchMinLengthHint => isRu
      ? 'Нужно хотя бы одно слово от трёх букв.'
      : "Kamida uch harfli so'z kiriting.";

  String get currencySom => isRu ? 'сум' : "so'm";

  // here rather than in one screen, because the pin label, the shop card and the home feed must agree
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
  String get changeCityLabel =>
      isRu ? 'Сменить город' : "Shaharni o'zgartirish";

  // nothing in the app produces a notification yet; the screen exists so the bell is a real destination
  String get notificationsTitle => isRu ? 'Уведомления' : 'Bildirishnomalar';
  String get noNotifications =>
      isRu ? 'Нет уведомлений' : "Bildirishnomalar yo'q";
  String get noNotificationsHint => isRu
      ? 'Здесь появятся новые заказы, ответы магазинов и новости Domix.'
      : "Bu yerda yangi buyurtmalar, do'konlar javoblari va Domix yangiliklari paydo bo'ladi.";

  // the Сообщения tab, held open while the feature behind it is rebuilt from nothing
  String get chatsScreenTitle => isRu ? 'Сообщения' : 'Xabarlar';
  String get chatsComingSoonTitle => isRu
      ? 'Скоро здесь будут сообщения'
      : "Tez orada bu yerda xabarlar bo'ladi";
  String get chatsComingSoonBody => isRu
      ? 'Переписка с магазинами и поддержкой Domix появится в одном из ближайших обновлений.'
      : "Do'konlar va Domix qo'llab-quvvatlash xizmati bilan yozishmalar yaqin yangilanishlarda paydo bo'ladi.";

  /// The sentence under a read that got no answer at all - [loadErrorHintFor]'s network case. An
  /// exception is written for whoever fixes it, never for whoever hit it, so the raw string goes to
  /// `debugPrint` and this goes on screen.
  String get loadErrorHint => isRu
      ? 'Проверьте подключение и попробуйте снова.'
      : "Ulanishni tekshirib, qayta urinib ko'ring.";

  /// The sentence under a failed read whose kind is known - see [LoadFailure]. **"Проверьте
  /// подключение" is only for [LoadFailure.network]**: over a busy server it sends somebody off to fix
  /// a connection that is working.
  String loadErrorHintFor(LoadFailure failure) => switch (failure) {
    LoadFailure.network => loadErrorHint,
    LoadFailure.busy =>
      isRu
          ? 'Сервер сейчас перегружен. Попробуйте через минуту.'
          : "Server hozir band. Bir daqiqadan so'ng urinib ko'ring.",
    LoadFailure.server =>
      isRu
          ? 'На сервере что-то пошло не так. Попробуйте позже.'
          : "Serverda nimadir noto'g'ri ketdi. Keyinroq urinib ko'ring.",
  };

  // anything older than yesterday gets its date, which is where "вчера" stops being information

  // ── Корзина: the list a customer sends to Domix, printed for staff as a накладная ──

  String get cartEmptyTitle =>
      isRu ? 'Соберите список покупок' : "Xaridlar ro'yxatini tuzing";
  String get cartEmptyBody => isRu
      ? 'Выберите категорию магазинов, заполните накладную или сфотографируйте свой список. Мы получим его сразу.'
      : "Do'konlar toifasini tanlang, yuk xatini to'ldiring yoki ro'yxatingizni suratga oling. Biz uni darhol olamiz.";
  String get cartNewButton => isRu ? 'Новая накладная' : 'Yangi yuk xati';
  String get cartLoadError =>
      isRu ? 'Не удалось загрузить накладные' : "Yuk xatlarini yuklab bo'lmadi";

  String waybillNumber(int number) =>
      isRu ? 'Накладная № $number' : 'Yuk xati № $number';
  String get waybillHeading => isRu ? 'Накладная' : 'Yuk xati';
  String get waybillNumberPending =>
      isRu ? '№ появится после отправки' : "№ yuborilgach paydo bo'ladi";
  String get waybillPhotoLabel => isRu ? 'Фото списка' : "Ro'yxat surati";

  String waybillRowCount(int count) {
    if (!isRu) return '$count ta qator';
    final tens = count % 100, ones = count % 10;
    if (tens >= 11 && tens <= 14) return '$count строк';
    if (ones == 1) return '$count строка';
    if (ones >= 2 && ones <= 4) return '$count строки';
    return '$count строк';
  }

  String get waybillCategoryTitle =>
      isRu ? 'В какие магазины?' : "Qaysi do'konlarga?";
  String get waybillCategoryHint => isRu
      ? 'Выберите категорию магазинов, где хотите купить товары.'
      : "Mahsulotlarni sotib olmoqchi bo'lgan do'konlar toifasini tanlang.";
  String waybillShopsLine(String category) =>
      isRu ? 'Магазины: $category' : "Do'konlar: $category";

  String get waybillModeForm => isRu ? 'Заполнить' : "To'ldirish";
  String get waybillModePhoto => isRu ? 'Фото списка' : "Ro'yxat surati";
  String get waybillColumnName => isRu ? 'Наименование' : 'Nomi';
  String get waybillColumnQuantity => isRu ? 'Кол-во' : 'Miqdori';
  String get waybillNameHint => isRu ? 'Товар' : 'Mahsulot';
  String get waybillQuantityHint => isRu ? '10 шт' : '10 ta';
  String get waybillAddRow => isRu ? 'Добавить строку' : "Qator qo'shish";
  String get waybillRowLimit => isRu
      ? 'В одной накладной до 100 строк'
      : 'Bitta yuk xatida 100 tagacha qator';
  String get waybillRemoveRow =>
      isRu ? 'Убрать строку' : 'Qatorni olib tashlash';
  String get waybillSend => isRu ? 'Отправить' : 'Yuborish';

  String get waybillPhotoPrompt => isRu
      ? 'Снимите весь лист при хорошем свете, чтобы можно было прочитать каждую строку.'
      : "Har bir qatorni o'qish mumkin bo'lishi uchun butun varaqni yaxshi yorug'likda suratga oling.";
  String get waybillTakePhoto => isRu ? 'Сфотографировать' : 'Suratga olish';
  String get waybillFromGallery => isRu ? 'Из галереи' : 'Galereyadan';
  String get waybillRetakePhoto => isRu ? 'Заменить' : 'Almashtirish';
  String get waybillPhotoError =>
      isRu ? 'Не удалось загрузить фото' : "Rasmni yuklab bo'lmadi";

  String get waybillAbandonTitle =>
      isRu ? 'Закрыть без отправки?' : 'Yubormasdan yopilsinmi?';
  String get waybillAbandonBody => isRu
      ? 'Всё, что вы заполнили, не сохранится.'
      : "To'ldirgan narsalaringiz saqlanmaydi.";
  String get waybillAbandonKeep => isRu ? 'Продолжить' : 'Davom etish';

  String get waybillSentDone => isRu ? 'Готово' : 'Tayyor';
  String waybillSentBody(String phone) => isRu
      ? 'Мы получили ваш список и свяжемся с вами по номеру $phone.'
      : "Ro'yxatingizni oldik va $phone raqami orqali siz bilan bog'lanamiz.";

  String get waybillEmptyError =>
      isRu ? 'Добавьте хотя бы один товар' : "Kamida bitta mahsulot qo'shing";
  String waybillRowIncomplete(int row) => isRu
      ? 'Заполните строку $row: нужны наименование и количество'
      : "$row-qatorni to'ldiring: nomi va miqdori kerak";
  String get waybillPhotoMissing =>
      isRu ? 'Добавьте фото списка' : "Ro'yxat suratini qo'shing";

  /// A send the server refused, by its stable code. Anything unrecognised reads as the connection,
  /// which is what nearly every failure on a phone is.
  String waybillSendError(String code) => switch (code) {
    'customers_only' =>
      isRu
          ? 'Корзина доступна только покупателям.'
          : 'Savat faqat xaridorlar uchun.',
    'too_many_waybills' =>
      isRu
          ? 'Слишком много накладных подряд. Подождите немного.'
          : "Ketma-ket juda ko'p yuk xati. Biroz kuting.",
    'picker_failed' =>
      isRu
          ? 'Не удалось открыть камеру или галерею.'
          : "Kamera yoki galereyani ochib bo'lmadi.",
    'image_too_large' =>
      isRu
          ? 'Фото слишком большое. Выберите другое.'
          : 'Rasm juda katta. Boshqasini tanlang.',
    'image_too_small' ||
    'invalid_image' ||
    'invalid_upload' ||
    'missing_image' =>
      isRu
          ? 'Это фото не подходит. Выберите другое.'
          : 'Bu rasm mos kelmaydi. Boshqasini tanlang.',
    // the server answered, so the connection is not what to check - and a retry is safe, it keeps its id
    'rate_limited' => loadErrorHintFor(LoadFailure.busy),
    'server_error' =>
      isRu
          ? 'Не удалось отправить. Попробуйте ещё раз чуть позже.'
          : "Yuborib bo'lmadi. Birozdan so'ng qayta urinib ko'ring.",
    _ =>
      isRu
          ? 'Не удалось отправить. Проверьте подключение и попробуйте ещё раз.'
          : "Yuborib bo'lmadi. Ulanishni tekshiring va qayta urinib ko'ring.",
  };

  // map screen (shop pins)
  String get noShopsYet =>
      isRu ? 'Пока нет магазинов' : "Hozircha do'konlar yo'q";

  /// the four category chips are a filter, so an empty map under one of them is a fact about the
  /// filter rather than about the city - saying the wrong one of the two sends the user looking for
  /// a bug
  String get noShopsInCategory => isRu
      ? 'В этой категории пока нет магазинов'
      : "Bu turdagi do'konlar hozircha yo'q";
  String get hideCategories => isRu ? 'Скрыть категории' : 'Turlarni yashirish';
  String get showCategories =>
      isRu ? 'Показать категории' : "Turlarni ko'rsatish";

  // «Рядом со мной» and the four ways the phone can decline to say where it is. two of them end on
  // a system page, which is what openSettingsButton is for.
  String get nearMe => isRu ? 'Рядом со мной' : 'Yaqinimda';

  /// the map hides the nav bar, so this disc is the only way back to the rest of the app
  String get exitMap => isRu ? 'На главную' : 'Bosh sahifaga';
  String get locationServicesOff =>
      isRu ? 'Включите геолокацию на телефоне' : 'Telefonda joylashuvni yoqing';
  String get locationDenied =>
      isRu ? 'Нужен доступ к геолокации' : 'Joylashuvga ruxsat kerak';
  String get locationDeniedForever => isRu
      ? 'Доступ к геолокации запрещён — разрешите его в настройках'
      : 'Joylashuvga ruxsat berilmagan — sozlamalardan ruxsat bering';
  String get locationUnavailable => isRu
      ? 'Не удалось определить местоположение'
      : "Joylashuvni aniqlab bo'lmadi";
  String get openSettingsButton => isRu ? 'Настройки' : 'Sozlamalar';

  /// The map's banner when the shop list did not arrive, by why - see [LoadFailure]. Two lines at most
  /// beside «Повторить», which is why it is not [loadErrorHintFor] appended to a title.
  String mapLoadErrorFor(LoadFailure failure) => switch (failure) {
    LoadFailure.network =>
      isRu
          ? 'Не удалось загрузить магазины. Проверьте подключение.'
          : "Do'konlarni yuklab bo'lmadi. Ulanishni tekshiring.",
    LoadFailure.busy =>
      isRu
          ? 'Сервер сейчас перегружен. Попробуйте через минуту.'
          : "Server hozir band. Bir daqiqadan so'ng urinib ko'ring.",
    LoadFailure.server =>
      isRu
          ? 'Не удалось загрузить магазины. Попробуйте позже.'
          : "Do'konlarni yuklab bo'lmadi. Keyinroq urinib ko'ring.",
  };
  String get loadingShops =>
      isRu ? 'Загружаем магазины...' : "Do'konlar yuklanmoqda...";

  // results are grouped: a shop the app already knows and a geocoded address are not the same answer
  String get mapSearchHint => isRu ? 'Магазин или адрес' : "Do'kon yoki manzil";
  String get searchSectionShops => isRu ? 'Магазины' : "Do'konlar";
  String get searchSectionPlaces => isRu ? 'Адреса' : 'Manzillar';
  String get searchNoResults =>
      isRu ? 'Ничего не найдено' : 'Hech narsa topilmadi';
  String get searchClear => isRu ? 'Очистить' : 'Tozalash';

  String get mapPlacesSearchFailed => isRu
      ? 'Не удалось найти адрес. Проверьте подключение.'
      : "Manzilni topib bo'lmadi. Ulanishni tekshiring.";

  /// the server answered and could not search - yandex down, or the day's budget spent - so the
  /// connection is not what to check
  String get mapPlacesSearchUnavailable => isRu
      ? 'Поиск адресов сейчас недоступен. Попробуйте позже или найдите место на карте.'
      : "Manzil qidiruvi hozir ishlamayapti. Keyinroq urinib ko'ring yoki joyni xaritadan toping.";
  String get mapShopsUnavailable =>
      isRu ? 'Магазины не загрузились' : "Do'konlar yuklanmadi";

  // the number is a labelled detail row, so the call button carries a verb instead of the raw number
  String get phoneLabel => isRu ? 'Телефон' : 'Telefon';
  String get callButton => isRu ? 'Позвонить' : "Qo'ng'iroq qilish";

  // location picker screen
  String get searchLocationHint =>
      isRu ? 'Поиск адреса...' : "Manzilni qidirish...";
  String get resolvingAddress =>
      isRu ? 'Определяем адрес...' : "Manzil aniqlanmoqda...";
  String get confirmLocationButton =>
      isRu ? 'Подтвердить местоположение' : "Joylashuvni tasdiqlash";

  // add store screen
  String get addStoreScreenTitle =>
      isRu ? 'Добавить магазин' : "Do'kon qo'shish";
  String get shopNameLabel => isRu ? 'Название магазина' : "Do'kon nomi";
  String get shopNameRequiredError => isRu
      ? 'Пожалуйста, введите название магазина'
      : "Iltimos, do'kon nomini kiriting";
  String get contactPhoneLabel =>
      isRu ? 'Контактный номер' : "Aloqa uchun raqam";
  String get contactPhoneRequiredError => isRu
      ? 'Пожалуйста, введите контактный номер'
      : "Iltimos, aloqa raqamini kiriting";
  String get locationLabel => isRu ? 'Местоположение' : "Joylashuv";
  String get pickLocationPrompt =>
      isRu ? 'Выбрать местоположение на карте' : "Xaritada joylashuvni tanlash";
  String get changeLocationButton => isRu ? 'Изменить' : "O'zgartirish";
  String get locationRequiredError => isRu
      ? 'Пожалуйста, выберите местоположение на карте'
      : "Iltimos, xaritada joylashuvni tanlang";
  // the category decides which ready-made catalogue is seeded, so the picker leads with its size
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

  // **Short on purpose.** These four share one strip on the map and one on the home screen, every
  // segment the same width, so a name is capped at about a quarter of a phone's width - the long
  // forms («Универсальный», «Пиломатериалы») ellipsed on every device we ship to.
  String get shopCategoryUniversal => isRu ? 'Разное' : 'Universal';
  String get shopCategoryPlumbing => isRu ? 'Сантехника' : 'Santexnika';
  // the stored code stays 'wood' - renaming it would be a data migration. it no longer matches
  // [categoryLumber] word for word, and that is fine: a kind of shop and a kind of product never
  // share a surface, and only this one has a quarter of a strip to fit into.
  String get shopCategoryWood => isRu ? 'Дерево' : "Yog'och";
  String get shopCategoryWallpaper => isRu ? 'Обои' : 'Oboylar';

  String get shopCategoryUniversalHint => isRu
      ? 'Всё для стройки: смеси, блоки, крепёж, электрика'
      : "Qurilish uchun hammasi: aralashmalar, bloklar, mahkamlagichlar, elektrika";
  String get shopCategoryPlumbingHint => isRu
      ? 'Трубы, фитинги, смесители, отопление'
      : "Quvurlar, fitinglar, smesitellar, isitish";
  // the label above already says "пиломатериалы", so repeating it would spend the line saying nothing
  String get shopCategoryWoodHint => isRu
      ? 'Брус, доска, рейка, фанера, стропила'
      : "Brus, doska, reyka, faner, stropila";
  // обои is the one category whose catalogue is places rather than products, and the category cannot
  // be changed afterwards
  String get shopCategoryWallpaperHint => isRu
      ? 'Места под ваши обои: премиум, стандарт, эконом'
      : "Oboylaringiz uchun joylar: premium, standart, ekonom";

  /// "Готовый каталог: 100 товаров" - shown under each category in the picker
  String readyCatalogLabel(int count) => isRu
      ? 'Готовый каталог: ${productsCountLabel(count)}'
      : "Tayyor katalog: ${productsCountLabel(count)}";

  String get createStoreButton => isRu ? 'Создать магазин' : "Do'kon yaratish";
  String get storeCreatedMessage => isRu
      ? 'Магазин успешно добавлен! 🎉'
      : "Do'kon muvaffaqiyatli qo'shildi! 🎉";

  /// Under the add-store form, by why the save failed - see [LoadFailure].
  String storeCreationFailedFor(LoadFailure failure) => switch (failure) {
    LoadFailure.network =>
      isRu
          ? 'Не удалось создать магазин. Проверьте подключение и попробуйте снова.'
          : "Do'konni yaratib bo'lmadi. Ulanishni tekshirib, qayta urinib ko'ring.",
    LoadFailure.busy => loadErrorHintFor(LoadFailure.busy),
    LoadFailure.server =>
      isRu
          ? 'Не удалось создать магазин. Попробуйте ещё раз чуть позже.'
          : "Do'konni yaratib bo'lmadi. Birozdan so'ng qayta urinib ko'ring.",
  };

  // my shops screen (list of shops the current owner has, opened from shopSettings above)
  String get myShopsScreenTitle => isRu ? 'Мои магазины' : "Mening do'konlarim";
  String get noOwnedShopsYet =>
      isRu ? 'У вас пока нет магазинов' : "Sizda hali do'konlar yo'q";
  String get noOwnedShopsHint => isRu
      ? 'Добавьте магазин, чтобы загрузить товары и появиться на карте'
      : "Mahsulot yuklash va xaritada ko'rinish uchun do'kon qo'shing";
  String get myShopsLoadError => isRu
      ? 'Не удалось загрузить ваши магазины'
      : "Do'konlaringizni yuklab bo'lmadi";
  String get showMoreButton => isRu ? 'Ещё' : "Yana ko'rsatish";
  String get retryButtonShort => isRu ? 'Повторить' : "Qayta urinish";
  String get noProductsYet => isRu ? 'Нет товаров' : "Mahsulot yo'q";

  // "5 магазинов" / "5 ta do'kon" - russian picks its noun form by the number, uzbek doesn't
  String shopsCountLabel(int count) => isRu
      ? '$count ${_ruPlural(count, 'магазин', 'магазина', 'магазинов')}'
      : "$count ta do'kon";
  String productsCountLabel(int count) => isRu
      ? '$count ${_ruPlural(count, 'товар', 'товара', 'товаров')}'
      : '$count ta mahsulot';

  // a menu of sections rather than one long page, so each needs a line saying what is behind it
  String get shopSettingsScreenTitle =>
      isRu ? 'Настройки магазина' : "Do'kon sozlamalari";
  String get sectionProductsTitle => isRu ? 'Товары' : 'Mahsulotlar';
  String get sectionProductsSubtitle => isRu
      ? 'Цены, наличие и свои товары'
      : "Narxlar, mavjudligi va o'z mahsulotlaringiz";
  String get sectionDetailsTitle =>
      isRu ? 'Данные магазина' : "Do'kon ma'lumotlari";
  String get sectionDetailsSubtitle => isRu
      ? 'Название, телефон, адрес и удаление'
      : "Nomi, telefoni, manzili va o'chirish";

  // edit shop screen (the "Данные магазина" section above)
  String get editStoreScreenTitle =>
      isRu ? 'Данные магазина' : "Do'kon ma'lumotlari";
  String get saveChangesButton =>
      isRu ? 'Сохранить изменения' : "O'zgarishlarni saqlash";
  String get storeUpdatedMessage =>
      isRu ? 'Изменения сохранены' : "O'zgarishlar saqlandi";
  String get noChangesToSave =>
      isRu ? 'Вы ничего не изменили' : "Siz hech narsani o'zgartirmadingiz";

  // the one irreversible action in the app, so it gets a red section header of its own
  String get dangerZoneTitle => isRu ? 'Удаление' : "O'chirish";
  String get deleteStoreButton =>
      isRu ? 'Удалить магазин' : "Do'konni o'chirish";
  String get deleteStoreHint => isRu
      ? 'Магазин исчезнет с карты вместе со всеми загруженными товарами. Действие необратимо.'
      : "Do'kon barcha yuklangan mahsulotlari bilan xaritadan yo'qoladi. Bu amalni qaytarib bo'lmaydi.";
  String get deleteStoreConfirmTitle =>
      isRu ? 'Удалить магазин?' : "Do'kon o'chirilsinmi?";
  String deleteStoreConfirmBody(String shopName, int productCount) {
    // naming the shop and counting what goes with it: "удалить?" alone gives nothing to check against
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

  // keyed off the backend's `code` - writeShopError in backend/internal/endpoints/shops.go
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
      // transient: the right advice is "press save again", not "check a connection that is working"
      case 'timeout':
        return isRu
            ? 'Сервер не ответил вовремя. Нажмите «Сохранить» ещё раз.'
            : "Server javob bermadi. «Saqlash»ni yana bosing.";
      // the server answered with something unplanned - not the phone's network, and retrying will not help
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

  // ── products: the owner's catalogue grid and the same grid on a shop's card. a shop is seeded at
  // creation, so most of these are about rows that have no price yet. ──

  String get productsScreenTitle => isRu ? 'Товары' : 'Mahsulotlar';
  // the same field spelled for a pill that shares its line with a button - the long hint ellipsised
  String get searchShortHint => isRu ? 'Поиск' : 'Qidiruv';
  String get productsScreenSubtitle => isRu
      ? 'Управляйте товарами вашего магазина'
      : "Do'koningiz mahsulotlarini boshqaring";
  // naming the two realistic causes at least points somewhere, which a bare "не удалось" does not

  String get productsLoadError =>
      isRu ? 'Не удалось загрузить товары' : "Mahsulotlarni yuklab bo'lmadi";
  String get noProductsInShop =>
      isRu ? 'В магазине пока нет товаров' : "Do'konda hozircha mahsulot yo'q";
  String get noProductsInShopHint => isRu
      ? 'Добавьте свои товары кнопкой ниже.'
      : "Quyidagi tugma orqali o'z mahsulotlaringizni qo'shing.";

  /// on a product with no price yet - the whole to-do list right after a shop is created
  String get priceNotSet => isRu ? 'Цена не указана' : "Narx ko'rsatilmagan";

  /// counts the basket rows only, because that is the count with a consequence attached
  String pricedProgressLabel(int priced, int total) => isRu
      ? 'Цены указаны: $priced из $total'
      : "Narxlar ko'rsatilgan: $total dan $priced";

  /// A shop joins the price comparison only once **every** basket product has a price (migration
  /// 000006), and that rule is invisible from anywhere else in the app. Two strings rather than one
  /// conditional: the completed state is the only positive confirmation the owner ever gets.
  String priceIndexNeedsEveryPrice(int remaining) => isRu
      ? 'Осталось $remaining — магазин попадёт в сравнение цен, когда указаны все'
      : "$remaining ta qoldi - barchasi ko'rsatilganda do'kon narx taqqoslashiga qo'shiladi";
  String get priceIndexParticipating => isRu
      ? 'Магазин участвует в сравнении цен'
      : "Do'kon narx taqqoslashida ishtirok etmoqda";

  /// on a catalogue product that is not part of the comparison yet - pricing it is welcome, leaving it
  /// empty costs the shop nothing, and an owner who does not know that prices it under pressure
  String get outsideBasketNote => isRu
      ? 'Этот товар пока не входит в сравнение цен: без цены магазин из сравнения не выпадет. Укажите её, когда будет удобно.'
      : "Bu mahsulot hozircha narx taqqoslashiga kirmaydi: narxsiz ham do'kon taqqoslashdan chiqmaydi. Qulay paytda ko'rsating.";

  // ── about. **Yandex's free terms ask for links to them in an «About» section**: the map's licence and
  // the maps service's own terms, which also cover the address search.
  String get aboutApp => isRu ? 'О приложении' : 'Ilova haqida';

  /// the document's own title: beside the maps service's terms, a shorter name read as the same link twice
  String get yandexMapsTerms => isRu
      ? 'Условия использования отдельных сервисов Яндекс Карт'
      : 'Yandex Xaritalar alohida xizmatlaridan foydalanish shartlari';

  /// **the wording is the terms' own (4.1.3.2)**, so it stays russian in both languages
  String get yandexMapsServiceTerms =>
      'Условия использования сервиса Яндекс.Карты';
  String get termsAndPrivacy => isRu
      ? 'Условия использования и конфиденциальность'
      : 'Foydalanish shartlari va maxfiylik';

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
  String get editProductTitle =>
      isRu ? 'Редактировать товар' : "Mahsulotni tahrirlash";
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
  String get productPriceHint => isRu
      ? 'Оставьте пустым, если цены пока нет'
      : "Narx hali bo'lmasa, bo'sh qoldiring";
  String get productPriceInvalidError =>
      isRu ? 'Введите цену числом' : "Narxni raqam bilan kiriting";
  String get productUnitLabel => isRu ? 'Единица измерения' : "O'lchov birligi";
  String get productUnitRequiredError =>
      isRu ? 'Укажите единицу измерения' : "O'lchov birligini ko'rsating";
  String get productAvailabilityLabel => isRu ? 'Наличие' : 'Mavjudligi';
  String get saveProductButton => isRu ? 'Сохранить' : 'Saqlash';
  String get productSavedMessage =>
      isRu ? 'Товар сохранён' : 'Mahsulot saqlandi';
  String get productDeletedMessage =>
      isRu ? 'Товар удалён' : "Mahsulot o'chirildi";
  String get deleteProductButton =>
      isRu ? 'Удалить товар' : "Mahsulotni o'chirish";
  String get deleteProductConfirmTitle =>
      isRu ? 'Удалить товар?' : "Mahsulot o'chirilsinmi?";
  String deleteProductConfirmBody(String productName) => isRu
      ? 'Товар «$productName» исчезнет из каталога магазина. Это действие нельзя отменить.'
      : "«$productName» mahsuloti do'kon katalogidan yo'qoladi. Bu amalni bekor qilib bo'lmaydi.";

  /// without it, a template row's missing controls read as a bug rather than as a rule
  String get templateProductHint => isRu
      ? 'Товар из готового каталога. Такие товары одинаковы во всех магазинах категории — поэтому здесь можно указать только цену и наличие, а удалить товар нельзя. Свои товары редактируются полностью.'
      : "Tayyor katalogdagi mahsulot. Bunday mahsulotlar kategoriyadagi barcha do'konlarda bir xil — shuning uchun bu yerda faqat narx va mavjudligini ko'rsatish mumkin, o'chirib bo'lmaydi. O'z mahsulotlaringiz to'liq tahrirlanadi.";

  /// the обои case: a template row whose product the owner supplies - a different rule from the one
  /// above, so a separate string
  String get slotProductHint => isRu
      ? 'Место под ваши обои. Класс и страну менять нельзя — по ним ваш магазин сравнивается с другими. Впишите свою коллекцию, цену за рулон и наличие. Удалить это место нельзя.'
      : "Sizning oboylaringiz uchun joy. Sinf va davlatni o'zgartirib bo'lmaydi — do'koningiz shular bo'yicha boshqalar bilan taqqoslanadi. O'z kolleksiyangizni, rulon narxini va mavjudligini kiriting. Bu joyni o'chirib bo'lmaydi.";

  /// placeholder in the name field of a слот, where the label alone would say nothing useful
  String get slotProductNameHint => isRu
      ? 'Например: Erismann Vlies 1,06 м'
      : "Masalan: Erismann Vlies 1,06 m";

  /// badge over the read-only fields of a template product
  String get templateFieldLocked => isRu ? 'Не изменяется' : "O'zgarmaydi";

  // the codes behind these live in the database (backend/db/migrations/000004)
  String get availabilityInStock => isRu ? 'Есть' : 'Bor';
  String get availabilityOnOrder => isRu ? 'Под заказ' : 'Buyurtma asosida';
  String get availabilityUnavailable => isRu ? 'Нет' : "Yo'q";

  /// The same three states **as a standalone badge on a product card**. The three above are the
  /// answers in the edit form's "Наличие:" dropdown, where the label supplies the noun; alone on a
  /// tile, "Есть" and "Нет" are fragments with nothing to answer.
  String get availabilityBadgeInStock => isRu ? 'В наличии' : 'Mavjud';
  String get availabilityBadgeOnOrder =>
      isRu ? 'Под заказ' : 'Buyurtma asosida';
  String get availabilityBadgeUnavailable =>
      isRu ? 'Нет в наличии' : 'Mavjud emas';

  /// The filter over a category's products. **"в категории", because it narrows what is already on
  /// screen** rather than searching the whole catalogue - the home bar is what does that, and a user
  /// who cannot tell the two apart will read an empty result as "Domix has none of these".
  String get categoryFilterHint =>
      isRu ? 'Поиск в категории' : 'Turkum ichidan qidirish';

  /// shown instead of the count once the search has left the category behind
  String get searchAcrossCategories =>
      isRu ? 'Поиск по всем категориям' : 'Barcha turkumlar bo\'yicha qidiruv';

  String get categoryFilterNoResults =>
      isRu ? 'В категории ничего не найдено' : 'Turkumda hech narsa topilmadi';

  /// **Names the escape hatch.** The filter narrows this category only, so a user who types a word
  /// that lives in another one sees nothing and concludes Domix does not stock it. The search key is
  /// what looks everywhere, and this is the only place that says so.
  String get categoryFilterNoResultsHint => isRu
      ? 'Нажмите «Поиск» на клавиатуре, чтобы искать по всем категориям.'
      : "Barcha turkumlar bo'yicha qidirish uchun klaviaturadagi «Qidirish» tugmasini bosing.";

  /// the heart on a product card - nothing reads it on screen, so it exists for screen readers
  String get addToFavouritesLabel => isRu ? 'В избранное' : 'Sevimlilarga';

  // customer-facing catalogue on a shop's card
  String get shopProductsSectionTitle => isRu ? 'Товары' : 'Mahsulotlar';
  String get noPricedProductsYet => isRu
      ? 'Магазин ещё не указал цены на товары'
      : "Do'kon hali mahsulot narxlarini ko'rsatmagan";

  /// names what it searches: «Поиск» alone would not say which of the app's two search fields this is
  String get shopProductsSearchHint => isRu
      ? 'Поиск по товарам магазина'
      : "Do'kon mahsulotlari bo'yicha qidirish";

  // keyed off the backend's `code` - writeAPIError in backend/internal/endpoints/authz.go
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
      // transient: the right advice is "press save again", not "check a connection that is working"
      case 'timeout':
        return isRu
            ? 'Сервер не ответил вовремя. Нажмите «Сохранить» ещё раз.'
            : "Server javob bermadi. «Saqlash»ni yana bosing.";
      // the server answered with something unplanned - not the phone's network, and retrying will not help
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

  // ── the shop card: only the labels that exist nowhere else ──

  /// named for the result rather than the mechanism, because which app answers depends on the phone
  String get routeButton => isRu ? 'Маршрут' : "Yo'nalish";

  /// url_launcher came back false: nothing on the phone would take the link. the number is on screen
  /// either way, which makes this a message rather than a failure.
  String get couldNotOpenExternalApp => isRu
      ? 'Не удалось открыть приложение на телефоне'
      : "Telefondagi ilovani ochib bo'lmadi";

  /// the two discs on the shop's cover carry no label, so these exist for a screen reader
  String get shareShopTooltip =>
      isRu ? 'Поделиться магазином' : "Do'kon bilan ulashish";
  String get copyPhoneTooltip =>
      isRu ? 'Скопировать номер' : 'Raqamdan nusxa olish';

  /// android 13 and later shows its own clipboard preview, so this doubles up there - and says the
  /// only thing an older phone says at all
  String get phoneCopied => isRu ? 'Номер скопирован' : 'Raqam nusxalandi';

  // ── the product photo an owner uploads. every product can carry one, template rows included:
  // comparability rests on the row's key, name and unit, none of which a photo touches. ──

  String get productPhotoLabel => isRu ? 'Фото товара' : 'Mahsulot rasmi';

  /// says what the photo is *for*, which is the only thing that makes an optional field worth filling in
  String get productPhotoHint => isRu
      ? 'Покупатели видят это фото в каталоге магазина.'
      : "Xaridorlar bu rasmni do'kon katalogida ko'radi.";

  /// worded as what the photo *is* rather than what the owner may not do - once that is said, the
  /// restriction explains itself
  String get cataloguePhotoNote => isRu
      ? 'Это фото из общего каталога — оно одинаковое во всех магазинах вашей категории, поэтому его нельзя заменить. Свои фото можно ставить на товары, которые вы добавили сами.'
      : "Bu umumiy katalogdagi rasm — u sizning kategoriyangizdagi barcha do'konlarda bir xil, shuning uchun uni almashtirib bo'lmaydi. O'z rasmlaringizni o'zingiz qo'shgan mahsulotlarga qo'ya olasiz.";

  String get addPhotoAction => isRu ? 'Добавить фото' : "Rasm qo'shish";
  String get changePhotoAction => isRu ? 'Заменить' : "Almashtirish";
  String get removePhotoAction => isRu ? 'Удалить фото' : "Rasmni o'chirish";

  String get photoSourceTitle =>
      isRu ? 'Откуда взять фото' : 'Rasmni qayerdan olamiz';
  String get photoFromCamera => isRu ? 'Сделать снимок' : 'Suratga olish';
  String get photoFromGallery =>
      isRu ? 'Выбрать из галереи' : 'Galereyadan tanlash';

  String get photoSavedMessage => isRu ? 'Фото сохранено' : 'Rasm saqlandi';
  String get photoRemovedMessage => isRu ? 'Фото удалено' : "Rasm o'chirildi";

  /// a product being created has no id to attach a photo to yet, so the picked file waits on the phone
  String get photoPendingSaveLabel => isRu
      ? 'Загрузится после сохранения товара'
      : 'Mahsulot saqlangach yuklanadi';

  /// the honest report of a half-success: the product was created and the photo was not
  String get productSavedWithoutPhoto => isRu
      ? 'Товар сохранён, но фото не загрузилось. Откройте товар и добавьте фото ещё раз.'
      : "Mahsulot saqlandi, lekin rasm yuklanmadi. Mahsulotni ochib, rasmni qayta qo'shing.";

  /// keyed off the backend's `code`, like [productErrorMessage]. separate because every message here
  /// is about a *file*, and a bad photo is not fixed by pressing save again.
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
      // the screen hides the control on a locked row, so this only reaches an app a build behind the rule
      case 'template_photo':
        return isRu
            ? 'Фото товара из общего каталога изменить нельзя.'
            : "Umumiy katalogdagi mahsulot rasmini o'zgartirib bo'lmaydi.";
      // the picker refused on the device - no camera, or access declined - so it has no server code
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
      // an upload is the one request in the app big enough to time out on a working connection
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
