// The substitution rule, tested where it actually matters: on screen.
//
// The showcase rows are temporary, but the *rule* about them is not obvious and is easy to break by
// accident - real data must win, invented data must never be mixed into a real list, and neither
// widget nor screen may contain any of that logic. These pin all three.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/data/home_showcase_content.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/screens/category_products_screen.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
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
  testWidgets('an empty backend falls back to the showcase rows', (tester) async {
    final controller = await _pumpHome(tester, _FakeHomeRepository(content: _content()));

    expect(controller.isShowingShowcase, isTrue);
    expect(controller.vipShops, kShowcaseVipShops);
    // the carousel renders the first showcase shop
    expect(find.text(kShowcaseVipShops.first.name), findsWidgets);
  });

  testWidgets('an unreachable backend falls back too, and keeps the error', (tester) async {
    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(error: Exception('connection refused')),
    );

    expect(controller.isShowingShowcase, isTrue);
    expect(controller.loadError, 'connection refused');
    // a demo on bad wifi shows shops, not three error states - but the cause is still recorded
    expect(controller.bestOffers, isNotEmpty);
  });

  testWidgets('real shops replace the showcase entirely - never a mix', (tester) async {
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

    expect(controller.isShowingShowcase, isFalse);
    expect(controller.bestOffers, hasLength(1));
    expect(controller.bestOffers.single.shops, hasLength(1));
    expect(find.text('Настоящий Дешёвый'), findsOneWidget);
    // the badge, never the raw index
    expect(find.text('на 12% дешевле рынка'), findsWidgets);

    // the one real offer is not padded out to ten with invented ones
    for (final showcase in kShowcaseBestOffers.expand((g) => g.shops)) {
      expect(find.text(showcase.name), findsNothing);
    }
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

  testWidgets('an empty VIP list omits the whole section, heading included', (tester) async {
    // reachable only with the showcase off, which is what production looks like
    final controller = HomeController(
      repository: _FakeHomeRepository(
        content: _content(offers: {
          ShopCategory.universal: [
            _shop(id: 2, name: 'Единственный', basketPrice: 5000000),
          ],
        }),
      ),
    );

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
    await tester.pumpAndSettle();

    expect(controller.vipShops, isEmpty);
    // a heading over blank space reads as broken, so it is not rendered at all
    expect(find.text('VIP Магазины'), findsNothing);
    expect(find.text('Лучшие предложения'), findsOneWidget);
  });
}
