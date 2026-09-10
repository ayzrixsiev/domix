import 'package:frontend/features/tickets/data/job_category.dart';
import 'package:frontend/features/tickets/data/job_ticket.dart';

/// The seeded job market: six workers and six open tickets, held in memory.
///
/// **Nothing here talks to the backend, and that is deliberate rather than unfinished** - what is
/// needed today is a walkable version of the marketplace, before a line of it is committed to a
/// schema. When it becomes a real feature the file is deleted whole and `TicketsController` grows a
/// repository, which is why the fixtures sit behind the controller rather than inside the widgets.
abstract final class DemoJobMarket {
  /// Ordered the way the server eventually should: available today first, then by rating.
  static final List<WorkerProfile> workers = [
    const WorkerProfile(
      name: DemoText('Алишер Каримов', 'Alisher Karimov'),
      skills: [JobCategory.finishing, JobCategory.tiling],
      experienceYears: 12,
      priceFrom: 450000,
      district: DemoText('Чиланзар', 'Chilonzor'),
      about: DemoText(
        'Отделка «под ключ»: штукатурка, шпаклёвка, покраска, укладка плитки. Работаю со своим инструментом.',
        "Kalit topshirish tamoyili bo'yicha pardozlash: shtukaturka, shpaklyovka, bo'yash, plitka yotqizish. O'z asbobim bilan ishlayman.",
      ),
      rating: 4.9,
      reviews: 87,
    ),
    const WorkerProfile(
      name: DemoText('Бахтиёр Юсупов', 'Baxtiyor Yusupov'),
      skills: [JobCategory.electric],
      experienceYears: 8,
      priceFrom: 380000,
      district: DemoText('Юнусабад', 'Yunusobod'),
      about: DemoText(
        'Электромонтаж квартир и офисов, щиты, проводка, розетки. Есть допуск и свои приборы.',
        "Kvartira va ofislarda elektr montaji, shchitlar, sim tortish, rozetkalar. Ruxsatnoma va o'z asboblarim bor.",
      ),
      rating: 4.8,
      reviews: 54,
    ),
    const WorkerProfile(
      name: DemoText('Санжар Тошматов', 'Sanjar Toshmatov'),
      skills: [JobCategory.plumbing, JobCategory.tiling],
      experienceYears: 6,
      priceFrom: 350000,
      district: DemoText('Мирзо-Улугбек', "Mirzo Ulug'bek"),
      about: DemoText(
        'Сантехника: разводка труб, установка ванн и унитазов, тёплый пол. Выезд по городу в тот же день.',
        "Santexnika: quvur tortish, vanna va unitaz o'rnatish, issiq pol. Shahar bo'ylab o'sha kuni chiqaman.",
      ),
      rating: 4.7,
      reviews: 41,
    ),
    const WorkerProfile(
      name: DemoText('Отабек Рахимов', 'Otabek Rahimov'),
      skills: [JobCategory.masonry, JobCategory.finishing],
      experienceYears: 15,
      priceFrom: 520000,
      district: DemoText('Сергели', 'Sergeli'),
      about: DemoText(
        'Бригада из четырёх человек. Кладка кирпича и блоков, фундамент, стяжка. Берём объёмы от 50 м².',
        "To'rt kishilik brigada. G'isht va blok terish, poydevor, styajka. 50 m² dan boshlab hajmli ishlarni olamiz.",
      ),
      rating: 4.9,
      reviews: 63,
      availableNow: false,
    ),
    const WorkerProfile(
      name: DemoText('Дилшод Назаров', 'Dilshod Nazarov'),
      skills: [JobCategory.carpentry],
      experienceYears: 9,
      priceFrom: 400000,
      district: DemoText('Яшнабад', 'Yashnobod'),
      about: DemoText(
        'Двери, кухни, встроенные шкафы. Замер бесплатно, работаю по чертежу заказчика или делаю свой.',
        "Eshiklar, oshxonalar, o'rnatma shkaflar. O'lchov bepul, buyurtmachi chizmasi bo'yicha yoki o'zim chizaman.",
      ),
      rating: 4.6,
      reviews: 29,
    ),
    const WorkerProfile(
      name: DemoText('Жасур Эргашев', 'Jasur Ergashev'),
      skills: [JobCategory.tiling, JobCategory.plumbing],
      experienceYears: 4,
      priceFrom: 300000,
      district: DemoText('Мирабад', 'Mirobod'),
      about: DemoText(
        'Плитка и керамогранит, санузлы под ключ. Недавно на Domix — цену держу ниже рынка.',
        "Plitka va keramogranit, kalit topshirish bilan sanuzellar. Domix'da yangiman — narxni bozordan past ushlayman.",
      ),
      rating: 5.0,
      reviews: 7,
    ),
  ];

  /// The open feed: what a worker scrolls, and - filtered to [JobTicket.needsMaterials] - what a shop
  /// owner watches.
  static final List<JobTicket> openTickets = [
    const JobTicket(
      id: 'demo-1',
      title: DemoText('Ремонт двухкомнатной квартиры', "Ikki xonali kvartirani ta'mirlash"),
      description: DemoText(
        'Новостройка, 62 м², голые стены. Нужна полная отделка: штукатурка, стяжка, обои, ламинат. Материалы за мой счёт.',
        "Yangi qurilgan uy, 62 m², devorlar yalang'och. To'liq pardoz kerak: shtukaturka, styajka, oboy, laminat. Materiallar mening hisobimdan.",
      ),
      category: JobCategory.finishing,
      budgetFrom: 18000000,
      district: DemoText('Юнусабад', 'Yunusobod'),
      postedAgo: Duration(hours: 2),
      authorName: DemoText('Нодира А.', 'Nodira A.'),
      responses: 4,
      needsMaterials: true,
    ),
    const JobTicket(
      id: 'demo-2',
      title: DemoText('Заменить проводку в квартире', "Kvartirada sim almashtirish"),
      description: DemoText(
        'Дом 1985 года, алюминий. Нужно поменять на медь, поставить новый щит и 14 розеток.',
        "1985-yilgi uy, alyuminiy sim. Misga almashtirish, yangi shchit va 14 ta rozetka o'rnatish kerak.",
      ),
      category: JobCategory.electric,
      budgetFrom: 6500000,
      district: DemoText('Чиланзар', 'Chilonzor'),
      postedAgo: Duration(hours: 5),
      authorName: DemoText('Шухрат М.', 'Shuhrat M.'),
      responses: 7,
      needsMaterials: true,
    ),
    const JobTicket(
      id: 'demo-3',
      title: DemoText('Санузел под ключ', 'Kalit topshirish bilan sanuzel'),
      description: DemoText(
        'Ванная 4 м². Снять старую плитку, развести трубы заново, положить керамогранит.',
        "Vannaxona 4 m². Eski plitkani olib tashlash, quvurlarni qaytadan tortish, keramogranit yotqizish.",
      ),
      category: JobCategory.plumbing,
      budgetFrom: 9000000,
      district: DemoText('Мирабад', 'Mirobod'),
      postedAgo: Duration(days: 1),
      authorName: DemoText('Азиза Т.', 'Aziza T.'),
      responses: 3,
      needsMaterials: true,
    ),
    const JobTicket(
      id: 'demo-4',
      title: DemoText('Кухонный гарнитур на заказ', 'Buyurtma asosida oshxona jihozi'),
      description: DemoText(
        'Угловая кухня 3,2 м. Нужен замер, изготовление и установка. Фурнитура — по вашему совету.',
        "Burchakli oshxona 3,2 m. O'lchov, tayyorlash va o'rnatish kerak. Furnitura — sizning maslahatingiz bo'yicha.",
      ),
      category: JobCategory.carpentry,
      budgetFrom: 12000000,
      district: DemoText('Мирзо-Улугбек', "Mirzo Ulug'bek"),
      postedAgo: Duration(days: 1, hours: 8),
      authorName: DemoText('Фаррух К.', 'Farrux K.'),
      responses: 2,
    ),
    const JobTicket(
      id: 'demo-5',
      title: DemoText('Кирпичный забор во дворе', 'Hovlida g\'ishtli devor'),
      description: DemoText(
        'Забор 24 погонных метра, высота 2 м, с двумя столбами под ворота. Кирпич куплю сам.',
        "24 pogon metr devor, balandligi 2 m, darvoza uchun ikkita ustun bilan. G'ishtni o'zim sotib olaman.",
      ),
      category: JobCategory.masonry,
      budgetFrom: 15000000,
      district: DemoText('Сергели', 'Sergeli'),
      postedAgo: Duration(days: 2),
      authorName: DemoText('Улугбек Р.', 'Ulug\'bek R.'),
      responses: 5,
      needsMaterials: true,
    ),
    const JobTicket(
      id: 'demo-6',
      title: DemoText('Положить плитку на балконе', 'Balkonga plitka yotqizish'),
      description: DemoText(
        'Балкон 6 м², плитка уже куплена. Нужен мастер на два дня.',
        "Balkon 6 m², plitka sotib olingan. Ikki kunga usta kerak.",
      ),
      category: JobCategory.tiling,
      budgetFrom: 2200000,
      district: DemoText('Яшнабад', 'Yashnobod'),
      postedAgo: Duration(days: 3),
      authorName: DemoText('Камола И.', 'Kamola I.'),
      responses: 9,
    ),
  ];

  /// What the signed-in client sees under «Мои заявки» before they post anything - two tickets in two
  /// different states, because a list where every row says the same thing teaches nothing.
  static final List<JobTicket> myTickets = [
    const JobTicket(
      id: 'mine-1',
      title: DemoText('Покрасить стены в гостиной', "Mehmonxona devorlarini bo'yash"),
      description: DemoText(
        'Комната 24 м², стены уже выровнены. Краска моя, нужен аккуратный маляр.',
        "Xona 24 m², devorlar tekislangan. Bo'yoq meniki, ozoda bo'yoqchi kerak.",
      ),
      category: JobCategory.finishing,
      budgetFrom: 3500000,
      district: DemoText('Чиланзар', 'Chilonzor'),
      postedAgo: Duration(hours: 4),
      authorName: DemoText('Вы', 'Siz'),
      responses: 3,
    ),
    const JobTicket(
      id: 'mine-2',
      title: DemoText('Установить смеситель и раковину', "Smesitel va rakovina o'rnatish"),
      description: DemoText(
        'Кухня, всё куплено. Старую раковину нужно снять и вынести.',
        "Oshxona, hammasi sotib olingan. Eski rakovinani olib chiqib ketish kerak.",
      ),
      category: JobCategory.plumbing,
      budgetFrom: 800000,
      district: DemoText('Чиланзар', 'Chilonzor'),
      postedAgo: Duration(days: 2),
      authorName: DemoText('Вы', 'Siz'),
      responses: 6,
      status: TicketStatus.inProgress,
    ),
  ];

  /// The анкета a worker lands on - **filled in, not blank.** The point of the screen is that a worker
  /// sees what a client will read, and an empty preview shows nothing at all. The name is overwritten
  /// with the signed-in account's own in [TicketsController].
  static const WorkerProfile draftProfile = WorkerProfile(
    name: DemoText('Ваша анкета', 'Sizning anketangiz'),
    skills: [JobCategory.finishing, JobCategory.tiling],
    experienceYears: 5,
    priceFrom: 400000,
    district: DemoText('Ташкент', 'Toshkent'),
    about: DemoText(
      'Расскажите о себе: что умеете, с каким инструментом работаете, берёте ли объёмы.',
      "O'zingiz haqingizda yozing: nima qila olasiz, qanday asbob bilan ishlaysiz, hajmli ishlarni olasizmi.",
    ),
  );
}
