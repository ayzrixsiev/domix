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
  String get innerManageStores =>
      isRu ? 'Настройка и статистика' : 'Sozlamalar va statistika';
  String get addStore => isRu ? 'Добавить новый магазин' : "Yangi do'kon qo'shish";
  String get backButton => isRu ? 'Назад в профиль' : 'Profilga qaytish';
  String get favorites => isRu ? 'Избранное' : 'Tanlanganlar';
  String get languageSettings => isRu ? 'Язык приложения' : 'Ilova tili';
  String get support => isRu ? 'Поддержка' : "Qo'llab-quvvatlash";
  String get logout => isRu ? 'Выйти из аккаунта' : 'Akkauntdan chiqish';
  String get selectLanguage => isRu ? 'Выберите язык' : 'Tilni tanlang';
  String get version => 'Domix • 1.0.0';

  String get registerTitle => isRu ? 'Регистрация' : "Ro'yxatdan o'tish";
  String get registerSubtitle => '';
  String get nameInputLabel => isRu ? 'Имя и фамилия' : "Ism va familiyangiz";
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

  // bottom navigation labels
  String get homeTab => isRu ? 'Главная' : 'Asosiy';
  String get searchTab => isRu ? 'Поиск' : 'Qidirish';
  String get mapTab => isRu ? 'Карта' : 'Xarita';
  String get messagesTab => isRu ? 'Сообщения' : 'Xabarlar';
  String get profileTab => isRu ? 'Профиль' : 'Profil';

  // home screen
  String get searchHint => isRu ? 'Поиск...' : 'Qidirish...';
  String get shopsNearbyTitle => isRu ? 'Магазины рядом с вами' : "Sizga yaqin do'konlar";
  String get popularProducts => isRu ? 'Популярные товары' : "Mashhur mahsulotlar";
  String get seeAll => isRu ? 'Все →' : "Hammasi →";
  String get popularShops => isRu ? 'Популярные магазины' : "Mashhur do'konlar";
  String get viewAll => isRu ? 'Смотреть все →' : "Hammasini ko'rish →";
  String get averageCheck => isRu ? 'Средний чек:' : "O'rtacha hisob:";
  String get cityName => isRu ? 'Ташкент' : 'Toshkent';

  // placeholder screens
  String get storesTitle => isRu ? 'Магазины' : "Do'konlar";
  String get storeFallback => isRu ? 'Магазин' : "Do'kon";
  String get messagesComingSoon => isRu
      ? 'Раздел сообщений скоро будет доступен'
      : "Xabarlar bo'limi tez orada bo'ladi";
  String get mapComingSoon => isRu
      ? 'Раздел карты скоро будет доступен'
      : "Xarita bo'limi tez orada bo'ladi";
  String get searchComingSoon => isRu
      ? 'Раздел поиска скоро будет доступен'
      : "Qidiruv bo'limi tez orada bo'ladi";
}
