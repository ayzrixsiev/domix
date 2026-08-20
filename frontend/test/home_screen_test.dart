// The home feed, tested where it matters: on screen.
//
// **The rule these exist for is that nothing here is invented.** There used to be a file of
// plausible shops the controller substituted whenever the backend came back empty or unreachable,
// and these tests pinned that substitution. It is deleted, and what replaced it is the harder thing
// to keep right: five VIP places and fifteen per category are drawn whether or not anybody has
// earned them, so the screen is now full of card-shaped things that must never acquire a name, an
// address or a price.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/screens/category_products_screen.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/home/presentation/widgets/home_shop_row.dart';
import 'package:frontend/features/home/presentation/widgets/vip_shops_carousel.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/location/presentation/controllers/city_controller.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// Stands in for the network. Returns whatever it is given, or throws if given an error.
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({
    this.content,
    this.error,
    this.categoryProducts = const [],
    this.searchResults = const [],
  });

  final HomeContent? content;
  final Object? error;
  final List<CategoryProduct> categoryProducts;
  final List<CategoryProduct> searchResults;

  ProductCategory? requestedCategory;
  String? requestedQuery;

  @override
  Future<HomeContent> fetchHomeContent() async {
    if (error != null) throw error!;
    return content!;
  }

  @override
  Future<List<CategoryProduct>> fetchProductsByCategory(ProductCategory category) async {
    requestedCategory = category;
    return categoryProducts;
  }

  @override
  Future<List<CategoryProduct>> searchProducts(String query) async {
    requestedQuery = query;
    return searchResults;
  }
}

Shop _shop({
  required int id,
  required String name,
  PriceTier? priceTier,
  int? differencePercent,
  int? basketPrice,
  bool isVip = false,
}) {
  return Shop(
    id: id,
    name: name,
    contactPhone: '+998901112233',
    address: 'Ташкент',
    category: ShopCategory.universal,
    latitude: 41.3,
    longitude: 69.2,
    rating: 4.5,
    priceTier: priceTier,
    priceDifferencePercent: differencePercent,
    basketPrice: basketPrice,
    isVip: isVip,
  );
}

HomeContent _content({
  List<Shop> vip = const [],
  Map<ShopCategory, List<Shop>> offers = const {},
}) {
  return HomeContent(
    vipShops: [for (final s in vip) HomeShopPreview.fromShop(s)],
    bestOffers: [
      for (final entry in offers.entries)
        CategoryOffers(
          category: entry.key,
          shops: [for (final s in entry.value) HomeShopPreview.fromShop(s)],
        ),
    ],
  );
}

Future<HomeController> _pumpHome(WidgetTester tester, _FakeHomeRepository repo) async {
  final controller = HomeController(repository: repo);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider<HomeController>.value(value: controller),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );

  // the load is kicked off from a post-frame callback, so one pump builds the frame and the
  // settle lets the future complete and the rebuild land
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  // **the state a fresh install is in, and the one that used to be covered up.** an empty database
  // draws all three sections at full size - five VIP places, twelve tiles, fifteen ranked places -
  // and not one shop name anywhere.
  testWidgets('an empty backend draws every section, never invented shops', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);
    final controller = await _pumpHome(tester, _FakeHomeRepository(content: _content()));

    expect(controller.vipShops, isEmpty);
    expect(controller.bestOffers, isEmpty);

    // **both shop sections draw, heading and all.** a section that vanished when it was empty read
    // as a screen missing a chunk of itself; the open places are the shape the feed has, and they
    // fill themselves in as shops finish pricing.
    expect(find.text(strings.vipShops), findsOneWidget);
    expect(find.text(strings.bestOffersTitle), findsOneWidget);
    expect(find.text(strings.slotShopNameLabel), findsWidgets);
    expect(find.text(strings.slotBasketLabel), findsWidgets);
    expect(find.byType(EmptyShopRow), findsNWidgets(BestOffersList.slotCount));

    // and no notice apologising for it. a screenful of designed-empty cards followed by "пока нет
    // магазинов" says the same thing twice, and the second time it reads as something being wrong.
    expect(find.text(strings.noShopsYet), findsNothing);
  });

  // ─────────────────────────── the carousel's geometry ───────────────────────────
  //
  // **`viewportFraction` and `_offCentreScaleDrop` are one dial pulled in opposite directions**, and
  // the thing they trade against each other is whether a reader can see there are more cards. The
  // card was widened once already; the next person to widen it will not have the arithmetic in front
  // of them, so it is pinned here at a real phone's width rather than at the test default of 800.
  testWidgets('the neighbouring cards stay visible at phone width', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(vip: [_shop(id: 1, name: 'Настоящий VIP', isVip: true)]),
      ),
    );

    // one PressableScale per built page; the transform that shrinks an off-centre card sits above
    // it, so a global rect already has the recede applied
    final cards = find.descendant(
      of: find.byType(VipShopsCarousel),
      matching: find.byType(PressableScale),
    );
    final rects = tester.widgetList(cards).indexed
        .map((e) => tester.getRect(cards.at(e.$1)))
        .toList()
      ..sort((a, b) => a.left.compareTo(b.left));

    expect(rects.length, greaterThan(1), reason: 'only one card was built - there is no peek at all');

    // the card to the right of the one in the middle: it has to start before the screen ends, or
    // the strip reads as a single card alone on the page rather than as a row of them
    final neighbour = rects.firstWhere((r) => r.left > 180);
    final visible = 360 - neighbour.left;
    expect(
      visible,
      greaterThan(8),
      reason: 'only ${visible.toStringAsFixed(1)}dp of the next card is on screen - widening the '
          'card or deepening the recede has closed the peek',
    );
  });

  testWidgets('an unreachable backend says so and offers a retry', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);
    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(error: Exception('connection refused')),
    );

    expect(controller.loadError, 'connection refused');
    // no plausible shops standing in for the ones we could not fetch - the failure is what is shown
    expect(controller.vipShops, isEmpty);
    expect(controller.bestOffers, isEmpty);

    // a *failure* still gets a block of its own, because that is the one thing the open places
    // cannot explain by themselves - and it is danger-coloured with a retry, not a friendly
    // "nothing here yet"
    expect(find.text(strings.homeLoadError), findsOneWidget);
    expect(find.text('connection refused'), findsOneWidget);
    expect(find.text(strings.retryButtonShort), findsOneWidget);
  });

  testWidgets('real shops fill the slots from the front, and nothing is invented', (tester) async {
    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(
          vip: [
            _shop(
              id: 1,
              name: 'Настоящий VIP',
              priceTier: PriceTier.dearer,
              differencePercent: 12,
              basketPrice: 5600000,
              isVip: true,
            ),
          ],
          offers: {
            ShopCategory.universal: [
              _shop(
                id: 2,
                name: 'Настоящий Дешёвый',
                priceTier: PriceTier.cheaper,
                differencePercent: 12,
                basketPrice: 4400000,
              ),
            ],
          },
        ),
      ),
    );

    expect(controller.bestOffers, hasLength(1));
    expect(controller.bestOffers.single.shops, hasLength(1));

    // the one sold placement is the card the carousel opens on rather than something two swipes
    // away behind empty ones - which is the difference between the section being worth money and not
    expect(find.text('Настоящий VIP'), findsOneWidget);

    expect(find.text('Настоящий Дешёвый'), findsOneWidget);
    // the badge, never the raw index
    expect(find.text('на 12% дешевле рынка'), findsWidgets);
  });

  testWidgets('a category tile opens onto that category\'s products', (tester) async {
    final repo = _FakeHomeRepository(
      content: _content(
        offers: {
          ShopCategory.universal: [
            _shop(id: 2, name: 'Настоящий', priceTier: PriceTier.cheaper,
                differencePercent: 12, basketPrice: 4400000),
          ],
        },
      ),
      // the drill-down's own list: products across every shop, each naming its seller
      categoryProducts: [
        CategoryProduct(
          shopName: 'Смеси Оптом',
          product: const Product(
            id: 3,
            shopId: 9,
            name: 'Цемент М400, 50 кг',
            category: 'mixes',
            unit: 'мешок',
            price: 88000,
            availability: ProductAvailability.inStock,
            isTemplate: true,
            nameEditable: false,
          ),
        ),
      ],
    );
    await _pumpHome(tester, repo);

    await tester.tap(find.byIcon(ProductCategory.mixes.icon));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryProductsScreen), findsOneWidget);
    // it asked the backend for the category that was tapped, and rendered what came back
    expect(repo.requestedCategory, ProductCategory.mixes);
    expect(find.text('Цемент М400, 50 кг'), findsOneWidget);
    expect(find.text('88 000 сум'), findsOneWidget);
    // the shop's name is on the tile - a price with no seller attached is not actionable
    expect(find.text('Смеси Оптом'), findsOneWidget);
  });

  // the home search bar spent three versions being a control that misbehaved - a styled `Text`, then
  // a real TextField with an empty `onSubmitted`, then a real TextField whose keyboard could not be
  // dismissed. these pin what it is now, because a regression in any of it is invisible: the bar
  // still looks right, and a query that never leaves the screen looks exactly like a search that
  // found nothing.
  //
  // **the home screen has no TextField at all any more**, which is the load-bearing half of the
  // keyboard fix - the field lives one route up, on ProductSearchScreen, where back dismisses it.
  testWidgets('the home search bar is a button, not a field', (tester) async {
    await _pumpHome(tester, _FakeHomeRepository(content: _content()));

    expect(find.byType(SearchAndLikeBar), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ProductSearchScreen), findsNothing);

    await tester.tap(find.byType(SearchAndLikeBar));
    await tester.pumpAndSettle();

    expect(find.byType(ProductSearchScreen), findsOneWidget);
    // autofocused, so the keyboard is already up when the screen arrives - the user tapped a search
    // bar to get here and should not have to tap a second one
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submitting the search field opens the results for what was typed', (tester) async {
    final repo = _FakeHomeRepository(
      content: _content(
        offers: {
          ShopCategory.universal: [
            _shop(id: 2, name: 'Настоящий', priceTier: PriceTier.cheaper,
                differencePercent: 12, basketPrice: 4400000),
          ],
        },
      ),
      searchResults: [
        CategoryProduct(
          shopName: 'Смеси Оптом',
          product: const Product(
            id: 3,
            shopId: 9,
            name: 'Цемент М400, 50 кг',
            category: 'mixes',
            unit: 'мешок',
            price: 88000,
            availability: ProductAvailability.inStock,
            isTemplate: true,
            nameEditable: false,
          ),
        ),
      ],
    );
    await _pumpHome(tester, repo);

    await tester.tap(find.byType(SearchAndLikeBar));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '  цемент  ');
    // testTextInput.receiveAction is how a widget test presses the keyboard's own search key -
    // there is no key to tap, so tapping cannot exercise onSubmitted at all
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // trimmed before it goes anywhere: the backend counts characters to decide the query is long
    // enough, and leading spaces would buy a search past that check with nothing in it
    expect(repo.requestedQuery, 'цемент');
    expect(find.text('Цемент М400, 50 кг'), findsOneWidget);
    expect(find.text('Смеси Оптом'), findsOneWidget);
    // the results replace the prompt on the same screen rather than pushing a second route - the
    // field stays reachable, which is what as-you-type will need
    expect(find.byType(ProductSearchScreen), findsOneWidget);
  });

  testWidgets('a one-letter search goes nowhere', (tester) async {
    // one character matches a large share of the catalogue, so the backend answers 400. this is the
    // app's half: the user is mid-word, and neither an error nor a screenful of noise is the right
    // response to that.
    final repo = _FakeHomeRepository(content: _content());
    await _pumpHome(tester, repo);

    await tester.tap(find.byType(SearchAndLikeBar));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ц');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repo.requestedQuery, isNull);
    // and the screen says why, rather than swallowing the press. the prompt is still on screen with
    // the "at least two characters" line under it.
    expect(find.text('Введите минимум два символа.'), findsOneWidget);
  });

  testWidgets('the category tiles carry no shop counts', (tester) async {
    // they did briefly, and it cost a database aggregate on every home load to tell a customer
    // something they had not asked. a tile is a way in, not a statistic.
    await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(offers: {
          ShopCategory.universal: [
            _shop(id: 2, name: 'Настоящий', basketPrice: 4400000),
          ],
        }),
      ),
    );

    // the grid is a two-page pager, so only the first eight tiles are built
    for (final category in ProductCategory.values.take(8)) {
      expect(find.byIcon(category.icon), findsWidgets);
    }
    // and no numeric badge anywhere on it
    for (final digit in ['0', '2', '3', '4', '7']) {
      expect(find.text(digit), findsNothing);
    }
  });

  // **the VIP heading now stays even with nothing sold, and Лучшие предложения still does not.**
  // The two look inconsistent and are not: five placements exist as a product whether or not anybody
  // has bought one, so their empty slots say "available". Лучшие предложения builds its tabs from
  // the data, so with nothing ranked there is no tab - and fifteen open places under a heading with
  // no filter above them would be a section about nothing.
  testWidgets('the VIP section is drawn with nothing sold', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);

    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(offers: {
          ShopCategory.universal: [
            _shop(id: 2, name: 'Единственный', basketPrice: 5000000),
          ],
        }),
      ),
    );

    expect(controller.vipShops, isEmpty);
    // the heading stays: five places exist as a product whether or not one has been bought, and the
    // empty card is what says so
    expect(find.text(strings.vipShops), findsOneWidget);
    expect(find.text(strings.slotShopNameLabel), findsWidgets);
    // the ranked category still has its own section
    expect(find.text(strings.bestOffersTitle), findsOneWidget);
    expect(find.text('Единственный'), findsOneWidget);
  });

  // the drill-down behind a category tile reads the database or shows an empty state. it used to
  // answer from the invented catalogue whenever the home screen was showing invented shops, so a
  // tapped tile opened onto plausible products at plausible prices from businesses that do not exist.
  testWidgets('a category with no products opens onto an empty state, not a story', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);
    final repo = _FakeHomeRepository(content: _content(), categoryProducts: const []);
    await _pumpHome(tester, repo);

    await tester.tap(find.byIcon(ProductCategory.mixes.icon));
    await tester.pumpAndSettle();

    expect(repo.requestedCategory, ProductCategory.mixes);
    expect(find.text(strings.noProductsInCategory), findsOneWidget);
    expect(find.byType(ProductTile), findsNothing);
  });
}
