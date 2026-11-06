import 'package:frontend/core/localization/app_localizations.dart';

/// The privacy policy shown during onboarding, in both of the app's languages.
///
/// **The same text is the page at `/privacy`** (backend/internal/webui/site/privacy.html), which also
/// carries an English version. It lives here as well so it can be read and accepted before an account
/// exists. `TestTheAppCarriesThePublishedPolicy` compares the two line by line: edit both, and move
/// [policyVersion] together with the api's `policyVersion`.
const String policyVersion = '2026-11-06';

/// One heading and the paragraphs under it. Bullets are plain strings beginning with "• ", so the
/// renderer stays a `Text` per line.
class PolicySection {
  const PolicySection({required this.title, required this.body});

  final String title;
  final List<String> body;
}

List<PolicySection> privacyPolicySections(AppLanguage language) =>
    language == AppLanguage.ru ? _russian : _uzbek;

/// What a reader takes away if they read nothing else. It promises nothing the sections do not.
String privacyPolicyLead(AppLanguage language) =>
    language == AppLanguage.ru ? _leadRu : _leadUz;

const String _leadRu =
    "Здесь мы объясняем, какие данные получает Domix, зачем они нужны и как их удалить. Если коротко:"
    " для входа нужен только номер телефона, ваше местоположение остаётся на телефоне, в нём нет "
    "сторонней рекламы, а данные мы не продаём.";

const String _leadUz =
    "Bu yerda Domix qanday ma’lumotlarni olishi, ular nima uchun kerakligi va ularni qanday o‘chirish"
    " mumkinligini tushuntiramiz. Qisqasi: kirish uchun faqat telefon raqami kerak, joylashuvingiz"
    " telefoningizda qoladi, unda begona reklama yo‘q, ma’lumotlarni esa sotmaymiz.";

const List<PolicySection> _russian = [
  PolicySection(
    title: "1. Кто мы",
    body: [
      "Domix разрабатывает и поддерживает команда Domix (далее — «мы»), г. Ташкент, Республика "
          "Узбекистан. Мы отвечаем за данные, о которых говорится в этой политике.",
      "Политика относится к мобильному приложению Domix для Android и к сайту domix-api.uz. Если "
          "у вас есть вопрос о ваших данных, пишите на domix.support@gmail.com.",
    ],
  ),
  PolicySection(
    title: "2. Какие данные мы получаем",
    body: [
      "• Номер телефона. Без него нельзя войти: на номер приходит код подтверждения, и по номеру "
          "мы узнаём вас при следующем входе.",
      "• Имя. Вы указываете его сами, оно отображается в вашем профиле.",
      "• Роль: покупатель или владелец магазина.",
      "• Данные магазина, если вы его открываете: название, адрес, точку на карте, контактный "
          "телефон, категорию, цены и фотографии товаров. Это витрина, поэтому её видят все "
          "пользователи приложения.",
      "• Избранное: товары, которые вы сохранили.",
      "• Списки покупок, если вы отправляете их из раздела «Корзина»: категорию магазинов, товары "
          "и количество или фотографию вашего списка. Их видят сотрудники Domix и магазины, которым мы пересылаем "
          "список вместе с вашим именем и номером телефона, чтобы они могли с вами связаться.",
      "• Технические данные. Когда приложение обращается к серверу, в журнал записываются IP-"
          "адрес, время и адрес запроса. Это нужно, чтобы защищать сервис от злоупотреблений и "
          "разбираться со сбоями.",
    ],
  ),
  PolicySection(
    title: "3. Чего мы не собираем",
    body: [
      "• Ваше местоположение. Мы его не получаем и не храним. Кнопка «Рядом со мной» на карте "
          "спрашивает у телефона, где вы, только в момент нажатия: координата нужна, чтобы сдвинуть "
          "карту к вам, и дальше вашего устройства она не уходит. Город и адрес магазина вы "
          "выбираете на карте сами.",
      "• Место съёмки фотографий. Камера телефона записывает в снимок координаты. Когда вы "
          "загружаете фото, мы пересохраняем его, и эти сведения удаляются.",
      "• Контакты, сообщения, файлы и рекламный идентификатор устройства.",
      "• Ничего для рекламы и аналитики: в Domix нет систем аналитики, трекеров и рекламных "
          "библиотек.",
      "• Пароли. В Domix их нет: вход только по одноразовому коду.",
      "Разрешение на геолокацию в карточке приложения в Google Play — от этой кнопки. Android "
          "спрашивает его в момент первого нажатия, отказаться можно, и всё остальное в приложении "
          "продолжит работать как прежде. Доступ к местоположению в фоне мы не запрашиваем.",
    ],
  ),
  PolicySection(
    title: "4. Зачем нам эти данные",
    body: [
      "• Чтобы вы могли войти, а мы — убедиться, что номер ваш.",
      "• Чтобы показывать магазины на карте и сравнивать их цены.",
      "• Чтобы покупатель мог связаться с магазином.",
      "• Чтобы обработать отправленный вами список покупок и связаться с вами по нему.",
      "• Чтобы защищать сервис от автоматических запросов и злоупотреблений.",
      "Мы обрабатываем данные с вашего согласия, которое вы даёте при регистрации, и только в том"
          " объёме, без которого приложение не может работать. Согласие можно отозвать в любой "
          "момент: для этого достаточно удалить аккаунт.",
    ],
  ),
  PolicySection(
    title: "5. Кто ещё получает данные",
    body: [
      "Мы не продаём данные и не передаём их другим компаниям для их собственных целей. Часть "
          "работы за нас делают сервисы-подрядчики, и каждый получает только то, что нужно для его "
          "задачи:",
      "• Telegram Gateway — номер телефона и код, чтобы доставить код подтверждения в Telegram.",
      "• Яндекс Карты (MapKit) — запросы карты, пока она открыта.",
      "• Геокодер и Геосаджест Яндекс Карт — текст, который вы вводите в поиске адреса, и координаты "
          "точки, которую вы поставили на карте, чтобы найти адрес. Запрос отправляет наш сервер, поэтому "
          "Яндекс не получает ни ваш IP-адрес, ни ваш аккаунт; ответы сервер помнит до недели, не связывая "
          "их с вами.",
      "• Cloudflare R2 — хранение фотографий товаров.",
      "• Хостинг-провайдер в Узбекистане — сервер и база данных.",
      "Государственным органам мы раскрываем данные только тогда, когда этого требует закон "
          "Республики Узбекистан.",
    ],
  ),
  PolicySection(
    title: "6. Где хранятся данные",
    body: [
      "Аккаунты, номера телефонов, магазины и списки покупок вместе с их фотографиями хранятся в "
          "базе данных на сервере в Республике Узбекистан.",
      "Telegram, Яндекс и Cloudflare работают за пределами Узбекистана. "
          "Поэтому то, что получает каждый из них (см. раздел 5), передаётся за рубеж: номер телефона"
          " — для доставки кода, адресные запросы и координаты точки — для поиска адреса, фотографии "
          "товаров — для хранения.",
    ],
  ),
  PolicySection(
    title: "7. Сколько мы храним данные",
    body: [
      "• Аккаунт, магазины, товары, списки покупок и избранное — пока вы пользуетесь Domix.",
      "• Код подтверждения — 5 минут. Он хранится только в оперативной памяти сервера и только в "
          "виде хэша, поэтому от начатой и брошенной регистрации ничего не остаётся.",
      "• Журналы сервера — до 90 дней.",
    ],
  ),
  PolicySection(
    title: "8. Ваши права и удаление аккаунта",
    body: [
      "Вы можете узнать, какие данные о вас у нас есть, исправить их или удалить. Имя, номер "
          "телефона и данные магазина меняются прямо в приложении, остальное — по письму на "
          "domix.support@gmail.com.",
      "Удалить аккаунт можно двумя способами:",
      "• в приложении: «Профиль» → «Удалить аккаунт»;",
      "• без приложения: на странице domix-api.uz/delete-account.",
      "Аккаунт удаляется сразу, а не по заявке. Вместе с ним удаляются ваши магазины, товары, "
          "списки покупок, загруженные фотографии и избранное. Восстановить их нельзя. В журналах сервера до 90 дней "
          "может остаться числовой номер удалённого аккаунта — без имени и телефона.",
    ],
  ),
  PolicySection(
    title: "9. Безопасность",
    body: [
      "Соединение с сервером зашифровано (TLS). Ключ сессии хранится в защищённом хранилище "
          "Android. Коды подтверждения хранятся только в виде хэша, а число попыток ввода ограничено.",
      "Полностью защищённых систем не бывает. Если заметили в своём аккаунте что-то "
          "подозрительное, напишите нам.",
    ],
  ),
  PolicySection(
    title: "10. Дети",
    body: [
      "Domix не рассчитан на детей младше 16 лет, и мы сознательно не собираем их данные. Если вы"
          " считаете, что ребёнок зарегистрировался в приложении, напишите нам, и мы удалим аккаунт.",
    ],
  ),
  PolicySection(
    title: "11. Изменения политики",
    body: [
      "Если мы существенно изменим политику, приложение покажет новую редакцию и снова попросит "
          "согласия. Дата текущей редакции указана в начале документа.",
    ],
  ),
  PolicySection(
    title: "12. Контакты",
    body: [
      "Вопросы о данных, просьбы исправить или удалить их присылайте на domix.support@gmail.com.",
    ],
  ),
];

const List<PolicySection> _uzbek = [
  PolicySection(
    title: "1. Biz kimmiz",
    body: [
      "Domix’ni Domix jamoasi («biz») ishlab chiqadi va qo‘llab-quvvatlaydi, Toshkent shahri, "
          "O‘zbekiston Respublikasi. Ushbu siyosatda so‘z yuritilgan ma’lumotlar uchun biz javob "
          "beramiz.",
      "Siyosat Android uchun Domix mobil ilovasiga va domix-api.uz saytiga tegishli. "
          "Ma’lumotlaringiz bo‘yicha savolingiz bo‘lsa, domix.support@gmail.com manziliga yozing.",
    ],
  ),
  PolicySection(
    title: "2. Qanday ma’lumotlarni olamiz",
    body: [
      "• Telefon raqami. Usiz kirib bo‘lmaydi: raqamga tasdiqlash kodi keladi, keyingi safar esa "
          "sizni shu raqam orqali taniymiz.",
      "• Ism. Uni o‘zingiz kiritasiz, u profilingizda ko‘rinadi.",
      "• Rol: xaridor yoki do‘kon egasi.",
      "• Do‘kon ma’lumotlari, agar do‘kon ochsangiz: nomi, manzili, xaritadagi nuqtasi, aloqa "
          "telefoni, toifasi, mahsulotlar narxi va suratlari. Bu vitrina, shuning uchun uni ilovaning"
          " barcha foydalanuvchilari ko‘radi.",
      "• Tanlanganlar: siz saqlab qo‘ygan mahsulotlar.",
      "• Xaridlar ro‘yxati, agar uni «Savat» bo‘limidan yuborsangiz: do‘konlar toifasi, mahsulotlar "
          "va miqdori yoki ro‘yxatingiz surati. Uni Domix xodimlari va ro‘yxat yuboriladigan do‘konlar ko‘radi: "
          "ular siz bilan bog‘lana olishi uchun ro‘yxat ismingiz va telefon raqamingiz bilan birga yuboriladi.",
      "• Texnik ma’lumotlar. Ilova serverga murojaat qilganda jurnalga IP manzil, vaqt va so‘rov "
          "manzili yoziladi. Bu xizmatni suiiste’moldan himoya qilish va nosozliklarni aniqlash uchun"
          " kerak.",
    ],
  ),
  PolicySection(
    title: "3. Nimalarni to‘plamaymiz",
    body: [
      "• Joylashuvingiz. Biz uni olmaymiz va saqlamaymiz. Xaritadagi «Yaqinimda» tugmasi telefondan"
          " qayerdaligingizni faqat siz bosgan paytda so‘raydi: koordinata xaritani sizga tomon "
          "surish uchun kerak va qurilmangizdan tashqariga chiqmaydi. Shahar va do‘kon manzilini "
          "xaritada o‘zingiz tanlaysiz.",
      "• Suratga olingan joy. Telefon kamerasi suratga koordinatalarni yozib qo‘yadi. "
          "Suratni yuklaganingizda biz uni qayta saqlaymiz va bu ma’lumotlar o‘chib ketadi.",
      "• Kontaktlar, xabarlar, fayllar va qurilmaning reklama identifikatori.",
      "• Reklama va tahlil uchun hech narsa: Domix’da tahlil tizimlari, kuzatuvchilar va reklama "
          "kutubxonalari yo‘q.",
      "• Parollar. Domix’da ular yo‘q: kirish faqat bir martalik kod orqali.",
      "Google Play’dagi ilova sahifasidagi geolokatsiya ruxsati — ana shu tugma uchun. Android uni"
          " birinchi marta bosganingizda so‘raydi, rad etishingiz mumkin, qolgan hamma narsa "
          "avvalgidek ishlaydi. Fon rejimida joylashuvga ruxsat so‘ramaymiz.",
    ],
  ),
  PolicySection(
    title: "4. Bu ma’lumotlar nima uchun kerak",
    body: [
      "• Siz kira olishingiz, biz esa raqam sizniki ekaniga ishonch hosil qilishimiz uchun.",
      "• Do‘konlarni xaritada ko‘rsatish va ularning narxlarini solishtirish uchun.",
      "• Xaridor do‘kon bilan bog‘lana olishi uchun.",
      "• Siz yuborgan xaridlar ro‘yxatini ko‘rib chiqish va shu bo‘yicha siz bilan bog‘lanish uchun.",
      "• Xizmatni avtomatik so‘rovlar va suiiste’moldan himoya qilish uchun.",
      "Ma’lumotlarni ro‘yxatdan o‘tishda bergan roziligingiz asosida va faqat ilova ishlashi "
          "uchun zarur hajmda qayta ishlaymiz. Rozilikni istalgan vaqtda qaytarib olish mumkin: "
          "buning uchun akkauntni o‘chirish kifoya.",
    ],
  ),
  PolicySection(
    title: "5. Ma’lumotlarni yana kim oladi",
    body: [
      "Biz ma’lumotlarni sotmaymiz va boshqa kompaniyalarga ularning o‘z maqsadlari uchun "
          "bermaymiz. Ishning bir qismini biz uchun pudratchi xizmatlar bajaradi va ularning har biri"
          " faqat o‘z vazifasi uchun keraklisini oladi:",
      "• Telegram Gateway — tasdiqlash kodini Telegram’ga yetkazish uchun telefon raqami va kod.",
      "• Yandex Xaritalar (MapKit) — xarita ochiq turganda uning so‘rovlari.",
      "• Yandex Xaritalar geokoderi va geosadjesti — manzilni topish uchun manzil qidiruvida yozgan "
          "matningiz va xaritada qo‘ygan nuqtangiz koordinatalari. So‘rovni bizning serverimiz yuboradi, "
          "shuning uchun Yandex IP-manzilingizni ham, akkauntingizni ham olmaydi; server javoblarni siz "
          "bilan bog‘lamasdan bir haftagacha eslab qoladi.",
      "• Cloudflare R2 — mahsulot suratlarini saqlash.",
      "• O‘zbekistondagi hosting-provayder — server va ma’lumotlar bazasi.",
      "Davlat organlariga ma’lumotlarni faqat O‘zbekiston Respublikasi qonunchiligi talab "
          "qilgandagina oshkor qilamiz.",
    ],
  ),
  PolicySection(
    title: "6. Ma’lumotlar qayerda saqlanadi",
    body: [
      "Akkauntlar, telefon raqamlari, do‘konlar va suratlari bilan birga xaridlar ro‘yxatlari "
          "O‘zbekiston Respublikasidagi serverda joylashgan ma’lumotlar bazasida saqlanadi.",
      "Telegram, Yandex va Cloudflare O‘zbekistondan tashqarida ishlaydi. "
          "Shuning uchun ularning har biri oladigan narsa (5-bo‘limga qarang) chet elga uzatiladi: "
          "telefon raqami — kodni yetkazish uchun, manzil so‘rovlari va nuqta koordinatalari — "
          "manzilni qidirish uchun, mahsulot suratlari — saqlash uchun.",
    ],
  ),
  PolicySection(
    title: "7. Ma’lumotlarni qancha saqlaymiz",
    body: [
      "• Akkaunt, do‘konlar, mahsulotlar, xaridlar ro‘yxatlari va tanlanganlar — Domix’dan foydalanar "
          "ekansiz.",
      "• Tasdiqlash kodi — 5 daqiqa. U faqat server tezkor xotirasida va faqat xesh ko‘rinishida "
          "saqlanadi, shuning uchun boshlangan va tashlab ketilgan ro‘yxatdan o‘tishdan hech narsa "
          "qolmaydi.",
      "• Server jurnallari — 90 kungacha.",
    ],
  ),
  PolicySection(
    title: "8. Huquqlaringiz va akkauntni o‘chirish",
    body: [
      "Siz haqingizda qanday ma’lumotlar borligini bilishingiz, ularni tuzatishingiz yoki "
          "o‘chirishingiz mumkin. Ism, telefon raqami va do‘kon ma’lumotlari bevosita ilovada "
          "o‘zgartiriladi, qolganlari — domix.support@gmail.com manziliga xat orqali.",
      "Akkauntni ikki yo‘l bilan o‘chirish mumkin:",
      "• ilovada: «Profil» → «Akkauntni o‘chirish»;",
      "• ilovasiz: domix-api.uz/delete-account sahifasida.",
      "Akkaunt ariza bo‘yicha emas, darhol o‘chiriladi. U bilan birga do‘konlaringiz, "
          "mahsulotlaringiz, xaridlar ro‘yxatlari, yuklangan suratlar va tanlanganlar ham o‘chiriladi. Ularni tiklab "
          "bo‘lmaydi. Server jurnallarida 90 kungacha o‘chirilgan akkauntning raqamli identifikatori "
          "qolishi mumkin — ismsiz va telefonsiz.",
    ],
  ),
  PolicySection(
    title: "9. Xavfsizlik",
    body: [
      "Server bilan aloqa shifrlangan (TLS). Sessiya kaliti Android’ning himoyalangan xotirasida "
          "saqlanadi. Tasdiqlash kodlari faqat xesh ko‘rinishida saqlanadi, kiritish urinishlari soni"
          " esa cheklangan.",
      "To‘liq himoyalangan tizimlar bo‘lmaydi. Akkauntingizda shubhali narsani sezsangiz, bizga "
          "yozing.",
    ],
  ),
  PolicySection(
    title: "10. Bolalar",
    body: [
      "Domix 16 yoshgacha bo‘lgan bolalar uchun mo‘ljallanmagan va biz ularning ma’lumotlarini "
          "ataylab to‘plamaymiz. Agar bola ilovada ro‘yxatdan o‘tgan deb hisoblasangiz, bizga yozing "
          "— akkauntni o‘chiramiz.",
    ],
  ),
  PolicySection(
    title: "11. Siyosatdagi o‘zgarishlar",
    body: [
      "Siyosatni jiddiy o‘zgartirsak, ilova yangi tahrirni ko‘rsatadi va rozilikni qaytadan "
          "so‘raydi. Joriy tahrir sanasi hujjat boshida ko‘rsatilgan.",
    ],
  ),
  PolicySection(
    title: "12. Aloqa",
    body: [
      "Ma’lumotlar bo‘yicha savollar, ularni tuzatish yoki o‘chirish haqidagi so‘rovlarni "
          "domix.support@gmail.com manziliga yuboring.",
    ],
  ),
];
