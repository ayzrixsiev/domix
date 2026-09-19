import 'package:frontend/core/localization/app_localizations.dart';

/// The privacy policy shown during onboarding, in both languages.
///
/// **Why this lives in the app as data rather than as a web page.** Google Play and the App Store
/// both require a policy that is readable *before* an account exists, and Play additionally wants
/// one reachable from a URL in the console listing. The same text serves both: this file is the
/// source, and the `/delete-account` page the API already serves is where the URL half will point.
///
/// **What it must actually cover**, and what a reviewer checks for: every category of personal data
/// collected, the purpose of each, who it is shared with (named, not "third parties"), how long it
/// is kept, and how to delete it. A policy that omits the deletion route is the single most common
/// rejection at review, which is why §7 names both routes.
///
/// **This is a competent draft, not legal advice.** [policyVersion] exists so that the day a lawyer
/// rewrites it, the app can tell who accepted which version - see [OnboardingFlow].
const String policyVersion = '2026-09-19';

/// One heading and the paragraphs under it. Bullets are plain strings beginning with "• " so the
/// renderer stays a `Text` per line rather than growing a markdown dependency for nine screens.
class PolicySection {
  const PolicySection({required this.title, required this.body});

  final String title;
  final List<String> body;
}

List<PolicySection> privacyPolicySections(AppLanguage language) =>
    language == AppLanguage.ru ? _russian : _uzbek;

/// The one-line summary above the scrollable policy: what a reader takes away if they read nothing
/// else. It is not a substitute for the sections below and deliberately makes no promise they do
/// not also make.
String privacyPolicyLead(AppLanguage language) => language == AppLanguage.ru
    ? 'Domix собирает минимум данных: номер телефона для входа, имя для обращения и — только если '
        'вы открываете магазин — его адрес на карте. Мы не продаём данные и не показываем рекламу '
        'сторонних сетей.'
    : "Domix eng kam ma'lumot to'playdi: kirish uchun telefon raqami, murojaat uchun ism va — agar "
        "do'kon ochsangiz — uning xaritadagi manzili. Biz ma'lumotlarni sotmaymiz va begona "
        "tarmoqlar reklamasini ko'rsatmaymiz.";

const List<PolicySection> _russian = [
  PolicySection(
    title: '1. Кто обрабатывает ваши данные',
    body: [
      'Оператором персональных данных является команда приложения Domix («мы»), Республика '
          'Узбекистан, г. Ташкент. Связаться с нами можно по адресу support@domix.uz или через '
          'раздел «Сообщения» внутри приложения.',
      'Настоящая политика описывает, какие данные собирает мобильное приложение Domix и что мы с '
          'ними делаем.',
    ],
  ),
  PolicySection(
    title: '2. Какие данные мы собираем',
    body: [
      '• Номер телефона — обязателен. Это ваш идентификатор в Domix: по нему выполняется вход и по '
          'нему покупатель связывается с магазином.',
      '• Имя — вы указываете его сами при регистрации. Отображается в вашем профиле и в переписке '
          'с поддержкой.',
      '• Роль — покупатель, рабочий или владелец магазина. Определяет, какие разделы приложения вам '
          'доступны.',
      '• Данные магазина — если вы открываете магазин: название, адрес, контактный телефон, '
          'категория, координаты на карте и фотографии товаров. Эти данные публичны по своей сути: '
          'магазин существует для того, чтобы его находили.',
      '• Сообщения в поддержку — текст ваших обращений и наши ответы.',
      '• Примерное местоположение — только когда вы сами открываете карту или выбираете адрес. '
          'Приложение не отслеживает вас в фоновом режиме.',
      '• Технические данные — IP-адрес и версия приложения, сохраняемые в журналах сервера для '
          'защиты от злоупотреблений и диагностики сбоев.',
    ],
  ),
  PolicySection(
    title: '3. Зачем мы их обрабатываем',
    body: [
      '• Чтобы создать учётную запись и подтвердить, что номер принадлежит вам.',
      '• Чтобы показать магазины на карте и сравнить цены между ними.',
      '• Чтобы покупатель мог связаться с магазином, а вы — с нашей поддержкой.',
      '• Чтобы ограничить количество запросов с одного устройства и защитить сервис от '
          'автоматических злоупотреблений.',
      'Мы не используем ваши данные для показа рекламы сторонних рекламных сетей и не составляем '
          'профили для рекламного таргетинга.',
    ],
  ),
  PolicySection(
    title: '4. Основание обработки',
    body: [
      'Мы обрабатываем данные на основании вашего согласия, которое вы даёте на этом экране, и в '
          'объёме, необходимом для исполнения нашего соглашения с вами — то есть для работы самого '
          'приложения. Согласие можно отозвать в любой момент, удалив учётную запись (см. §7).',
    ],
  ),
  PolicySection(
    title: '5. Кому мы передаём данные',
    body: [
      'Мы не продаём персональные данные и не передаём их третьим лицам для их собственных целей. '
          'Мы пользуемся следующими поставщиками услуг, каждый из которых обрабатывает строго '
          'необходимый минимум:',
      '• Оператор SMS/сообщений (Eskiz.uz или Telegram Gateway) — получает ваш номер телефона, '
          'чтобы доставить одноразовый код подтверждения.',
      '• Yandex MapKit — обрабатывает картографические запросы, когда вы открываете карту.',
      '• Cloudflare R2 — хранит загруженные фотографии товаров.',
      '• Хостинг-провайдер в Республике Узбекистан — размещает серверы приложения и базу данных.',
      'Мы также раскрываем данные, если этого требует закон Республики Узбекистан по обоснованному '
          'запросу уполномоченного органа.',
    ],
  ),
  PolicySection(
    title: '6. Сколько мы храним данные',
    body: [
      '• Учётная запись, магазины и товары — пока вы пользуетесь Domix. При удалении учётной записи '
          'они удаляются вместе с ней.',
      '• Одноразовые коды подтверждения — не более 5 минут, после чего удаляются. Сам код мы '
          'храним только в виде необратимого хэша.',
      '• Сообщения в поддержку — до удаления учётной записи.',
      '• Журналы сервера — до 90 дней.',
    ],
  ),
  PolicySection(
    title: '7. Ваши права и удаление данных',
    body: [
      'Вы вправе получить доступ к своим данным, исправить их и удалить. Имя и данные магазина '
          'редактируются прямо в приложении.',
      'Удалить учётную запись можно двумя способами:',
      '• В приложении: «Профиль» → «Удалить аккаунт».',
      '• Без установки приложения: на странице https://domix.uz/delete-account.',
      'Удаление необратимо. Вместе с учётной записью удаляются ваши магазины, товары, загруженные '
          'фотографии и переписка с поддержкой.',
    ],
  ),
  PolicySection(
    title: '8. Безопасность',
    body: [
      'Соединение приложения с сервером защищено TLS. Токен вашей сессии хранится в защищённом '
          'хранилище операционной системы устройства. Коды подтверждения хранятся только в виде '
          'хэша и ограничены по числу попыток ввода.',
      'Ни один способ передачи данных не защищён абсолютно, и мы не можем гарантировать абсолютную '
          'безопасность.',
    ],
  ),
  PolicySection(
    title: '9. Дети',
    body: [
      'Domix не предназначен для лиц младше 16 лет, и мы сознательно не собираем их данные. Если вы '
          'считаете, что ребёнок передал нам свои данные, напишите на support@domix.uz — мы удалим '
          'их.',
    ],
  ),
  PolicySection(
    title: '10. Изменения политики',
    body: [
      'При существенном изменении этой политики мы покажем её новую редакцию в приложении и '
          'запросим согласие заново. Дата текущей редакции указана в начале документа.',
    ],
  ),
];

const List<PolicySection> _uzbek = [
  PolicySection(
    title: "1. Ma'lumotlaringizni kim qayta ishlaydi",
    body: [
      "Shaxsiy ma'lumotlar operatori — Domix ilovasi jamoasi («biz»), O'zbekiston Respublikasi, "
          "Toshkent shahri. Biz bilan support@domix.uz orqali yoki ilovadagi «Xabarlar» bo'limi "
          "orqali bog'lanishingiz mumkin.",
      "Ushbu siyosat Domix mobil ilovasi qanday ma'lumotlarni to'plashini va ular bilan nima "
          "qilishimizni tushuntiradi.",
    ],
  ),
  PolicySection(
    title: "2. Qanday ma'lumotlarni to'playmiz",
    body: [
      "• Telefon raqami — majburiy. Bu Domix'dagi identifikatoringiz: kirish shu orqali amalga "
          "oshiriladi va xaridor do'kon bilan shu orqali bog'lanadi.",
      "• Ism — ro'yxatdan o'tishda o'zingiz kiritasiz. Profilingizda va qo'llab-quvvatlash bilan "
          "yozishmada ko'rinadi.",
      "• Rol — xaridor, ishchi yoki do'kon egasi. Ilovaning qaysi bo'limlari ochiqligini "
          "belgilaydi.",
      "• Do'kon ma'lumotlari — agar do'kon ochsangiz: nomi, manzili, aloqa telefoni, toifasi, "
          "xaritadagi koordinatalari va mahsulot suratlari. Bu ma'lumotlar tabiatan ochiq: do'kon "
          "topilishi uchun mavjud.",
      "• Qo'llab-quvvatlashga xabarlar — murojaatlaringiz matni va bizning javoblarimiz.",
      "• Taxminiy joylashuv — faqat siz xaritani ochganingizda yoki manzil tanlaganingizda. Ilova "
          "sizni fonda kuzatmaydi.",
      "• Texnik ma'lumotlar — IP manzil va ilova versiyasi; suiiste'moldan himoya va nosozliklarni "
          "aniqlash uchun server jurnallarida saqlanadi.",
    ],
  ),
  PolicySection(
    title: "3. Nima uchun qayta ishlaymiz",
    body: [
      "• Hisob yaratish va raqam sizga tegishli ekanini tasdiqlash uchun.",
      "• Do'konlarni xaritada ko'rsatish va narxlarni taqqoslash uchun.",
      "• Xaridor do'kon bilan, siz esa qo'llab-quvvatlash bilan bog'lana olishingiz uchun.",
      "• Bitta qurilmadan so'rovlar sonini cheklash va xizmatni avtomatik suiiste'moldan himoya "
          "qilish uchun.",
      "Biz ma'lumotlaringizdan begona reklama tarmoqlari reklamasini ko'rsatish uchun "
          "foydalanmaymiz va reklama maqsadida profil tuzmaymiz.",
    ],
  ),
  PolicySection(
    title: "4. Qayta ishlash asosi",
    body: [
      "Ma'lumotlarni ushbu ekranda bergan roziligingiz asosida va siz bilan tuzilgan kelishuvni "
          "bajarish — ya'ni ilovaning ishlashi — uchun zarur hajmda qayta ishlaymiz. Rozilikni "
          "istalgan vaqtda hisobni o'chirish orqali qaytarib olishingiz mumkin (7-bandga qarang).",
    ],
  ),
  PolicySection(
    title: "5. Ma'lumotlarni kimga beramiz",
    body: [
      "Biz shaxsiy ma'lumotlarni sotmaymiz va uchinchi shaxslarga o'z maqsadlari uchun bermaymiz. "
          "Quyidagi xizmat yetkazib beruvchilardan foydalanamiz, ularning har biri faqat zarur "
          "minimumni qayta ishlaydi:",
      "• SMS/xabar operatori (Eskiz.uz yoki Telegram Gateway) — bir martalik tasdiqlash kodini "
          "yetkazish uchun telefon raqamingizni oladi.",
      "• Yandex MapKit — xaritani ochganingizda karta so'rovlarini qayta ishlaydi.",
      "• Cloudflare R2 — yuklangan mahsulot suratlarini saqlaydi.",
      "• O'zbekiston Respublikasidagi hosting-provayder — ilova serverlari va ma'lumotlar bazasini "
          "joylashtiradi.",
      "Shuningdek, vakolatli organning asoslangan so'rovi bo'yicha O'zbekiston Respublikasi "
          "qonunchiligi talab qilsa, ma'lumotlarni oshkor qilamiz.",
    ],
  ),
  PolicySection(
    title: "6. Ma'lumotlarni qancha saqlaymiz",
    body: [
      "• Hisob, do'konlar va mahsulotlar — Domix'dan foydalanganingizcha. Hisobni o'chirganingizda "
          "ular ham o'chiriladi.",
      "• Bir martalik tasdiqlash kodlari — ko'pi bilan 5 daqiqa, so'ng o'chiriladi. Kodning o'zini "
          "faqat qaytarib bo'lmaydigan xesh ko'rinishida saqlaymiz.",
      "• Qo'llab-quvvatlashga xabarlar — hisob o'chirilgunga qadar.",
      "• Server jurnallari — 90 kungacha.",
    ],
  ),
  PolicySection(
    title: "7. Huquqlaringiz va ma'lumotlarni o'chirish",
    body: [
      "Siz o'z ma'lumotlaringizni olish, to'g'rilash va o'chirish huquqiga egasiz. Ism va do'kon "
          "ma'lumotlari bevosita ilovada tahrirlanadi.",
      "Hisobni ikki yo'l bilan o'chirish mumkin:",
      "• Ilovada: «Profil» → «Hisobni o'chirish».",
      "• Ilovani o'rnatmasdan: https://domix.uz/delete-account sahifasida.",
      "O'chirish qaytarib bo'lmaydi. Hisob bilan birga do'konlaringiz, mahsulotlaringiz, yuklangan "
          "suratlar va qo'llab-quvvatlash bilan yozishma o'chiriladi.",
    ],
  ),
  PolicySection(
    title: "8. Xavfsizlik",
    body: [
      "Ilovaning server bilan aloqasi TLS bilan himoyalangan. Sessiya tokeni qurilma operatsion "
          "tizimining himoyalangan xotirasida saqlanadi. Tasdiqlash kodlari faqat xesh ko'rinishida "
          "saqlanadi va kiritish urinishlari soni cheklangan.",
      "Ma'lumot uzatishning hech bir usuli mutlaq himoyalangan emas va biz mutlaq xavfsizlikni "
          "kafolatlay olmaymiz.",
    ],
  ),
  PolicySection(
    title: "9. Bolalar",
    body: [
      "Domix 16 yoshga to'lmagan shaxslar uchun mo'ljallanmagan va biz ularning ma'lumotlarini "
          "ataylab to'plamaymiz. Agar bola bizga o'z ma'lumotlarini bergan deb hisoblasangiz, "
          "support@domix.uz ga yozing — biz ularni o'chiramiz.",
    ],
  ),
  PolicySection(
    title: "10. Siyosat o'zgarishlari",
    body: [
      "Ushbu siyosat jiddiy o'zgarganda, uning yangi tahririni ilovada ko'rsatamiz va rozilikni "
          "qaytadan so'raymiz. Joriy tahrir sanasi hujjat boshida ko'rsatilgan.",
    ],
  ),
];
