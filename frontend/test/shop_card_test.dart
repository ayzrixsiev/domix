// One shop card, reached from three places.
//
// **a route that does not open the card is a tap that does nothing** - no error anywhere, the app
// looks finished and ignores the finger. These pin the two routes into it, and the one row that must
// *not* open one.
//
// The empty-slot case is the subtle one: both home sections draw a fixed number of places whether or
// not shops filled them, so an unsold VIP slot must stay inert rather than opening a card about a
// business that does not exist.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/location/presentation/controllers/city_controller.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/data/product_section.dart';
import 'package:frontend/features/products/data/products_repository.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';
import 'package:frontend/features/stores/presentation/widgets/shop_category_avatar.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Stands in for the network. `implements` rather than a subclass, so the fake cannot accidentally
/// inherit a real http call the day one is added to the repository.
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({required this.content});

  final HomeContent content;

  @override
  Future<HomeContent> fetchHomeContent() async => content;

  @override
  Future<List<CategoryProduct>> fetchProductsByCategory(
    ProductCategory category,
  ) async => const [];

  @override
  Future<List<CategoryProduct>> searchProducts(
    String query, {
    int offset = 0,
  }) async => const [];

  @override
  Future<List<String>> suggestProducts(String query) async => const [];
}

class _FakeProductsRepository implements ProductsRepository {
  _FakeProductsRepository({this.products = const []});

  final List<Product> products;
  int fetches = 0;

  @override
  Future<List<Product>> fetchShopProducts(int shopId) async {
    fetches++;
    return products;
  }

  @override
  Future<Product> createProduct({
    required int shopId,
    required Product draft,
  }) async => draft;

  @override
  Future<Product> updateProduct(Product product) async => product;

  @override
  Future<void> deleteProduct(int productId) async {}

  @override
  Future<Product> uploadProductImage({
    required int productId,
    required String filePath,
  }) async => products.firstWhere((p) => p.id == productId);

  @override
  Future<Product> removeProductImage(int productId) async =>
      products.firstWhere((p) => p.id == productId);
}

/// Stands in for the phone's url handler. **`launchUrl` answers true or false and nothing else**,
/// so this is the only way to see *which* link «Маршрут» handed over.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({this.installed = const ['yandexmaps', 'https']});

  /// The url schemes this phone pretends to have an app for.
  final List<String> installed;
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (!installed.contains(Uri.parse(url).scheme)) return false;
    launched.add(url);
    return true;
  }
}

Shop _shop({required int id, required String name, bool isVip = false}) {
  return Shop(
    id: id,
    name: name,
    contactPhone: '+998901112233',
    address: 'ул. Навои 12',
    category: ShopCategory.universal,
    latitude: 41.3,
    longitude: 69.2,
    priceTier: PriceTier.cheaper,
    priceDifferencePercent: 4,
    basketPrice: 4850000,
    isVip: isVip,
  );
}

Product _product({
  required int id,
  required String name,
  int? price,
  String specs = '',
  ProductSection? section,
}) {
  return Product(
    id: id,
    shopId: 1,
    name: name,
    category: 'tools',
    unit: 'шт',
    price: price,
    availability: ProductAvailability.inStock,
    isTemplate: true,
    nameEditable: false,
    specs: specs,
    section: section,
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required HomeContent content,
  List<Product> products = const [],
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(
          create: (_) =>
              HomeController(repository: _FakeHomeRepository(content: content)),
        ),
        ChangeNotifierProvider(
          create: (_) => ProductsController(
            repository: _FakeProductsRepository(products: products),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  // the feed loads from a post-frame callback, so one pump builds the frame and the settle lets the
  // future land
  await tester.pumpAndSettle();
}

HomeContent _content({
  List<Shop> vip = const [],
  List<Shop> offers = const [],
}) {
  return HomeContent(
    vipShops: [for (final s in vip) HomeShopPreview.fromShop(s)],
    bestOffers: [
      if (offers.isNotEmpty)
        CategoryOffers(
          category: ShopCategory.universal,
          shops: [for (final s in offers) HomeShopPreview.fromShop(s)],
        ),
    ],
  );
}

void main() {
  test(
    'the catalogue is read once a session, and again after the app is reopened',
    () async {
      final repo = _FakeProductsRepository();
      final controller = ProductsController(repository: repo);

      await controller.loadProducts(1);
      await controller.loadProducts(1);
      expect(repo.fetches, 1, reason: 'browsing must not re-read prices');

      controller.markAllStale();
      await controller.loadProducts(1);
      expect(repo.fetches, 2, reason: 'coming back into the app re-reads them');
    },
  );

  testWidgets('a VIP card opens the shop card', (tester) async {
    await _pumpHome(
      tester,
      content: _content(
        vip: [_shop(id: 1, name: 'ВИП Стройбаза', isVip: true)],
      ),
    );

    expect(find.byType(ShopCardScreen), findsNothing);

    // `.hitTestable()`, not `.first`: the carousel is an endless PageView, so with one shop the
    // same card is also built as the page either side of the viewport. `.first` picks one of those,
    // at a negative offset, and taps nothing.
    await tester.tap(find.text('ВИП Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardScreen), findsOneWidget);
    // the two facts the sheet used to be opened for, and the reason a card exists at all
    expect(find.text('+998901112233'), findsOneWidget);
    expect(find.text('ул. Навои 12'), findsWidgets);
  });

  testWidgets('a Лучшие предложения row opens the same card', (tester) async {
    await _pumpHome(
      tester,
      content: _content(offers: [_shop(id: 2, name: 'Дешёвый Склад')]),
    );

    // scrolled to first: the VIP carousel is five permanent places now, so Лучшие предложения starts
    // below the fold and `tap` on an off-screen widget lands nowhere
    await tester.ensureVisible(find.text('Дешёвый Склад').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Дешёвый Склад').first);
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardScreen), findsOneWidget);
    expect(find.text('Дешёвый Склад'), findsWidgets);
  });

  // an unsold VIP place is drawn as a card and is not one. tapping it must do nothing at all -
  // there is no shop behind it, and a route into an address nobody is at is worse than an inert card.
  testWidgets('an empty VIP slot opens nothing', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);
    await _pumpHome(tester, content: _content());

    // the label where a real card would carry the shop's name
    await tester.tap(
      find.text(strings.slotShopNameLabel).hitTestable().first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardScreen), findsNothing);
  });

  // the customer-facing rule: an unpriced row is the *owner's* to-do list and answers nothing for a
  // buyer, so it is not on their card at all
  testWidgets('the card lists only the products that carry a price', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        _product(id: 10, name: 'Цемент М400', price: 55000),
        _product(id: 11, name: 'Гипсокартон'),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    // the catalogue is below the cover, the identity block, the price card and the contacts card, so
    // it is a sliver that has not been built yet - scrolling is what asks for it
    await _scrollToCatalogue(tester);

    expect(find.text('Цемент М400'), findsOneWidget);
    expect(find.text('Гипсокартон'), findsNothing);
    expect(find.byType(ProductTile), findsOneWidget);
  });

  // a shop owner opening another shop: the server sends its priced rows with no price. they are
  // still the catalogue, so they draw - and a null price must not read as «Цена не указана»
  testWidgets('a hidden price is a priced row, with no amount and a reason', (
    tester,
  ) async {
    final strings = AppLocalizations(AppLanguage.ru);
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: const [
        Product(
          id: 10,
          shopId: 1,
          name: 'Цемент М400',
          category: 'tools',
          unit: 'шт',
          price: null,
          priceHidden: true,
          availability: ProductAvailability.inStock,
          isTemplate: true,
          nameEditable: false,
        ),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    expect(find.text('Цемент М400'), findsOneWidget);
    expect(find.text(strings.priceHidden), findsOneWidget);
    expect(find.text(strings.priceNotSet), findsNothing);
    expect(find.text(strings.pricesHiddenForSellers), findsOneWidget);
  });

  // the reason the field exists: a Универсальный shop is a hundred tiles, and scrolling all of them
  // to find one is not a way to find anything. it filters what is already on the phone - the whole
  // catalogue came in the one request this screen makes - so there is no request behind a keystroke.
  testWidgets('the catalogue search filters the grid', (tester) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        for (var i = 0; i < 9; i++)
          _product(id: 20 + i, name: 'Саморез $i', price: 1000 + i),
        _product(id: 40, name: 'Цемент М400', price: 55000),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    await tester.enterText(find.byType(TextField), 'цемент');
    await tester.pumpAndSettle();

    expect(find.text('Цемент М400'), findsOneWidget);
    expect(find.text('Саморез 0'), findsNothing);
  });

  // the size is in the description now, so «125» has to find the 125 mm disc
  testWidgets('the catalogue search reads the description too', (tester) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        for (var i = 0; i < 8; i++)
          _product(id: 20 + i, name: 'Саморез $i', price: 1000 + i),
        _product(
          id: 40,
          name: 'Алмазный диск',
          specs: '125 мм · 1ADP · EPA',
          price: 90000,
        ),
        _product(
          id: 41,
          name: 'Алмазный диск',
          specs: '180 мм · 1ADP · EPA',
          price: 120000,
        ),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    await tester.enterText(find.byType(TextField), '125');
    await tester.pumpAndSettle();

    expect(find.textContaining('125 мм · 1ADP · EPA'), findsOneWidget);
    expect(find.textContaining('180 мм · 1ADP · EPA'), findsNothing);
  });

  // over the search threshold, so the row the disc lives on is drawn - under it a catalogue is
  // already entirely on screen and has nothing to filter
  List<Product> sectioned() => [
    for (var i = 0; i < 7; i++)
      _product(
        id: 20 + i,
        name: 'Саморез $i',
        price: 1000 + i,
        section: ProductSection.fastenersMounting,
      ),
    _product(
      id: 10,
      name: 'Розетка двойная',
      price: 25000,
      section: ProductSection.electricalLighting,
    ),
    _product(
      id: 11,
      name: 'Дюбель',
      price: 300,
      section: ProductSection.fastenersMounting,
    ),
  ];

  // the chips are gone: the disc beside the field is the one way to the sections, and the sheet is
  // where the full names and the counts are
  testWidgets('the sections disc opens the sheet and a pick narrows the grid', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: sectioned(),
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    final strings = AppLocalizations(AppLanguage.ru);
    await tester.tap(find.byIcon(LucideIcons.sliders_horizontal));
    await tester.pumpAndSettle();

    // the sheet carries the whole name, which a chip did not
    expect(find.text(strings.sectionFullElectricalLighting), findsOneWidget);

    await tester.tap(find.text(strings.sectionFullElectricalLighting));
    await tester.pumpAndSettle();

    expect(find.text('Розетка двойная'), findsOneWidget);
    expect(find.text('Дюбель'), findsNothing);
  });

  // the sections do not ride on the search field's threshold: a catalogue too short to be worth
  // searching can still be split, and then the sections are a button of their own
  testWidgets('a short catalogue keeps its sections without a search field', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        _product(
          id: 10,
          name: 'Розетка двойная',
          price: 25000,
          section: ProductSection.electricalLighting,
        ),
        _product(
          id: 11,
          name: 'Дюбель',
          price: 300,
          section: ProductSection.fastenersMounting,
        ),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    final strings = AppLocalizations(AppLanguage.ru);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(strings.sectionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.sectionFullElectricalLighting));
    await tester.pumpAndSettle();

    expect(find.text('Розетка двойная'), findsOneWidget);
    expect(find.text('Дюбель'), findsNothing);
  });

  // one section is nothing to choose between, so the field takes the whole line
  testWidgets('a single-section catalogue gets no sections disc', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        for (var i = 0; i < 9; i++)
          _product(
            id: 20 + i,
            name: 'Саморез $i',
            price: 1000 + i,
            section: ProductSection.fastenersMounting,
          ),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    expect(find.byIcon(LucideIcons.sliders_horizontal), findsNothing);
  });

  // **the magnifier is part of the control, and it used not to be.** a TextField only takes focus
  // where the TextField is, and this one is the Expanded in the middle of a row - so the padding,
  // the magnifier and the gap after it were about 40px of dead surface at the left end of something
  // that looks exactly like a button. pressing it and having nothing happen is the whole of "the
  // search button does not work", and nothing about it is visible in a screenshot.
  testWidgets('tapping the magnifier focuses the catalogue search', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [
        for (var i = 0; i < 9; i++)
          _product(id: 20 + i, name: 'Саморез $i', price: 1000 + i),
      ],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.tap(find.byIcon(LucideIcons.search));
    await tester.pumpAndSettle();

    expect(field.focusNode!.hasFocus, isTrue);
  });

  // under the threshold the field is not drawn at all. a search box over three products filters a
  // list that is already entirely on screen, which is a control that can only ever hide things.
  testWidgets('a short catalogue gets no search field', (tester) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      products: [_product(id: 10, name: 'Цемент М400', price: 55000)],
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();
    await _scrollToCatalogue(tester);

    expect(find.byType(ProductTile), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  // **the mark on the card and the glyph in the map pin are the same character.** almost every way
  // into a shop is a pin, and a card that opened under a different mark reads as the wrong shop.
  testWidgets('the mark carries the shop category', (tester) async {
    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ShopCategoryAvatar),
        matching: find.byIcon(ShopCategory.universal.icon),
      ),
      findsOneWidget,
    );
  });

  // the number is on the card to be used somewhere else - pasted into a chat, saved as a contact -
  // and a long-press on a Text selects nothing at all
  testWidgets('the copy disc puts the number on the clipboard', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _pumpHome(
      tester,
      content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
    );

    await tester.tap(find.text('Стройбаза').hitTestable().first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.copy));
    await tester.pumpAndSettle();

    expect(copied, '+998901112233');
  });

  // what the share sheet is handed. there is no page per shop and no deep link, so this text *is*
  // the share - a url pointing at us would be a promise the build cannot keep.
  testWidgets(
    'sharing hands over the name, the address, the number and a map link',
    (tester) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      String? shared;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        shared = (call.arguments as Map)['text'] as String?;
        return 'dev.fluttercommunity.plus/share/success';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await _pumpHome(
        tester,
        content: _content(vip: [_shop(id: 1, name: 'Стройбаза', isVip: true)]),
      );

      await tester.tap(find.text('Стройбаза').hitTestable().first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.share));
      await tester.pumpAndSettle();

      expect(shared, contains('Стройбаза'));
      expect(shared, contains('ул. Навои 12'));
      expect(shared, contains('+998901112233'));
      expect(shared, contains('69.2,41.3'));
    },
  );

  // the map's half of the card: the same content in a sheet that a downward drag puts away. there is
  // no close button on it, so if the drag ever stops dismissing there is no way out but the back
  // gesture - which is exactly the kind of failure nobody notices until a phone is in a hand.
  testWidgets('the map sheet opens the same card and a drag down closes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(
            create: (_) =>
                ProductsController(repository: _FakeProductsRepository()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showShopCardSheet(context, _shop(id: 7, name: 'Стройбаза')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ShopCardView), findsOneWidget);
    expect(find.text('+998901112233'), findsOneWidget);

    // from the top of the list, a downward drag is the sheet's and not the scroll view's - that
    // handover is what DraggableScrollableSheet's controller does, and it is the whole gesture
    await tester.drag(find.byType(ShopCardView), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(find.byType(ShopCardView), findsNothing);
  });

  // **The coordinates go out in the order the receiving app reads them, and a swap fails silently:**
  // Yandex's `rtext` is latitude,longitude while its `pt` is longitude,latitude, so a card that sent
  // 69.2,41.3 would open a map of empty steppe in Kazakhstan with no error anywhere. 41.3 and 69.2
  // are far enough apart to catch it.
  testWidgets('«Маршрут» hands the shop to Yandex Maps as a route', (
    tester,
  ) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    await _pumpCard(tester);
    await tester.tap(find.text('Маршрут'));
    await tester.pumpAndSettle();

    expect(
      launcher.launched.single,
      'yandexmaps://maps.yandex.ru/?rtext=~41.3,69.2&rtt=auto',
      reason: 'latitude first, and the empty point means "from where I am"',
    );
  });

  testWidgets('without Yandex Maps the route falls to Google', (tester) async {
    // a phone with a browser and no yandex app: the first link throws ActivityNotFoundException,
    // which url_launcher reports as false
    final launcher = _FakeUrlLauncher(installed: const ['https']);
    UrlLauncherPlatform.instance = launcher;

    await _pumpCard(tester);
    await tester.tap(find.text('Маршрут'));
    await tester.pumpAndSettle();

    expect(
      launcher.launched.single,
      'https://www.google.com/maps/dir/'
      '?api=1&destination=41.3,69.2&travelmode=driving',
    );
  });
}

Future<void> _pumpCard(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(
          create: (_) =>
              ProductsController(repository: _FakeProductsRepository()),
        ),
      ],
      child: MaterialApp(
        home: ShopCardScreen(shop: _shop(id: 1, name: 'Стройбаза')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The catalogue is the last thing on a card that now opens with a full-width cover, so every
/// assertion about a tile has to build the sliver first.
Future<void> _scrollToCatalogue(WidgetTester tester) async {
  await tester.drag(find.byType(ShopCardView), const Offset(0, -600));
  await tester.pumpAndSettle();
}
