// The home feed, tested where it matters: on screen.
//
// **The rule these exist for is that nothing here is invented**: no plausible shop is ever
// substituted for an empty or unreachable backend. five VIP places and fifteen per category are drawn
// whether or not anybody has earned them, so the screen is full of card-shaped things that must never
// acquire a name, an address or a price.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/data/home_repository.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/screens/category_products_screen.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
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

  /// the offset of every search request, in order - what "Ещё" is checked against
  final List<int> requestedOffsets = [];

  /// how many times the feed has actually been fetched - the only way to tell a refresh that ran
  /// from one whose gesture was never recognised, which is how pull-to-refresh fails
  int fetchCount = 0;

  @override
  Future<HomeContent> fetchHomeContent() async {
    fetchCount++;
    if (error != null) throw error!;
    return content!;
  }

  @override
  Future<List<CategoryProduct>> fetchProductsByCategory(
    ProductCategory category,
  ) async {
    requestedCategory = category;
    return categoryProducts;
  }

  @override
  Future<List<CategoryProduct>> searchProducts(
    String query, {
    int offset = 0,
  }) async {
    requestedQuery = query;
    requestedOffsets.add(offset);
    // sliced the way the server pages: the rows already held are the offset
    return searchResults
        .skip(offset)
        .take(HomeRepository.searchPageSize)
        .toList();
  }

  @override
  Future<List<String>> suggestProducts(String query) async => const [];
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

Future<HomeController> _pumpHome(
  WidgetTester tester,
  _FakeHomeRepository repo,
) async {
  final controller = HomeController(repository: repo);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => CityController()),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
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

CategoryProduct _lamp(int id) => CategoryProduct(
  shopName: 'Магазин $id',
  product: Product(
    id: id,
    shopId: id,
    name: 'Лампа $id',
    category: 'electrical',
    unit: 'шт',
    price: 10000 + id,
    availability: ProductAvailability.inStock,
    isTemplate: true,
    nameEditable: false,
  ),
);

void main() {
  // **the state a fresh install is in, and the one that used to be covered up.** an empty database
  // draws all three sections at full size - five VIP places, eight category cards, fifteen ranked
  // places - and not one shop name anywhere.
  testWidgets('an empty backend draws every section, never invented shops', (
    tester,
  ) async {
    final strings = AppLocalizations(AppLanguage.ru);
    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(content: _content()),
    );

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

  // a seller is sent no ranking and must not learn that anything is withheld: no section, no note,
  // and no fifteen open places that would read as nobody being ranked
  testWidgets('a seller gets no ranking section at all', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);
    await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: const HomeContent(
          vipShops: [],
          bestOffers: [],
          indexHidden: true,
        ),
      ),
    );

    expect(find.text(strings.bestOffersTitle), findsNothing);
    expect(find.byType(EmptyShopRow), findsNothing);
  });

  // signing in as a shop owner changes what the server answers, and the home tab is kept alive by
  // the shell - nothing would ask again. a change mid-load is followed by one more load.
  testWidgets('a change of account re-reads home, even mid-load', (
    tester,
  ) async {
    final repo = _FakeHomeRepository(content: _content());
    final controller = await _pumpHome(tester, repo);
    expect(repo.fetchCount, 1);

    controller.handleViewerChanged();
    await tester.pumpAndSettle();
    expect(repo.fetchCount, 2);

    final load = controller.loadHome(force: true);
    controller.handleViewerChanged();
    await load;
    await tester.pumpAndSettle();
    expect(repo.fetchCount, 4);
  });

  // ─────────────────────────── the carousel's geometry ───────────────────────────
  //
  // **One card fills the page now, so nothing on screen peeks.** The strip used to show a sliver of
  // its neighbours, and that sliver was what told a reader there were more placements; the dots
  // carry that job alone, and there has to be one per slot or the section stops saying how much
  // inventory it has. Pinned at a real phone's width rather than at the test default of 800.
  testWidgets('one card across the page, with a dot for every slot under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(
          vip: [_shop(id: 1, name: 'Настоящий VIP', isVip: true)],
        ),
      ),
    );

    // the card is the page, inset by the feed's own gutter on each side
    final cards = find.descendant(
      of: find.byType(VipShopsCarousel),
      matching: find.byType(PressableScale),
    );
    expect(
      tester.getRect(cards.first).width,
      closeTo(360 - VipShopsCarousel.cardGutter * 2, 0.5),
      reason: 'the card no longer fills the page between the gutters',
    );

    // one dot per slot, sold or not: five dots over one card is the section saying there are four
    // more placements behind this one
    final dots = find.descendant(
      of: find.byType(VipShopsCarousel),
      matching: find.byType(AnimatedContainer),
    );
    expect(dots, findsNWidgets(VipShopsCarousel.slotCount));

    // and exactly one of them is the wide one - at 6px a colour change on its own is a detail
    // somebody has to go looking for
    final widths = [
      for (var i = 0; i < VipShopsCarousel.slotCount; i++)
        tester.getSize(dots.at(i)).width,
    ];
    final widest = widths.reduce((a, b) => a > b ? a : b);
    expect(
      widths.where((w) => w == widest),
      hasLength(1),
      reason: 'no single dot is marked as the one in front',
    );
    expect(widths.where((w) => w != widest), everyElement(lessThan(widest)));
  });

  // **The strip moves with nobody touching it**, which is what makes the four placements behind the
  // first one worth selling - and **the finger wins over the clock**, because a tick firing mid-drag
  // would animate the page away from the person holding it. one card is one whole page, so "it moved"
  // is the sold card no longer being on screen at all.
  testWidgets('the carousel advances on its own, and a finger on it stops the clock', (
    tester,
  ) async {
    final strings = AppLocalizations(AppLanguage.ru);
    await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(
          vip: [_shop(id: 1, name: 'Настоящий VIP', isVip: true)],
        ),
      ),
    );

    // the sold card opens in front - vipSlotRing put it there
    final card = find.text('Настоящий VIP');
    expect(card, findsOneWidget);

    // one dwell with nobody touching anything, and the next slot has the page
    await tester.pump(VipShopsCarousel.autoAdvanceEvery);
    await tester.pumpAndSettle();
    expect(
      card,
      findsNothing,
      reason:
          'the sold card is still on screen - the strip never advanced by itself',
    );

    // **now a finger, held still, and it has to win.** on the empty slot the strip has moved to,
    // which is also what keeps this from opening a shop: an unsold slot is inert. measured after
    // the press lands, since a card shrinking under a thumb is not the strip moving.
    final slot = find.text(strings.slotShopNameLabel).first;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VipShopsCarousel)),
    );
    await tester.pumpAndSettle();
    final held = tester.getRect(slot);

    await tester.pump(
      VipShopsCarousel.autoAdvanceEvery + const Duration(seconds: 1),
    );
    // and a settle, because a tick that did fire would only show up on the frames after it
    await tester.pumpAndSettle();

    expect(
      tester.getRect(slot),
      held,
      reason:
          'the carousel advanced out from under a finger that was holding it',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // **pull-to-refresh is the gesture that fails silently.** nothing throws when the scroll physics
  // do not allow an overscroll - the finger just drags and nothing happens - so the only honest
  // assertion is that the repository was asked a second time.
  testWidgets('pulling the feed down opens the gap, spins in it, and refetches', (
    tester,
  ) async {
    final repo = _FakeHomeRepository(content: _content());
    await _pumpHome(tester, repo);
    expect(repo.fetchCount, 1, reason: 'the initial load');

    // no spinner on a feed that is sitting still
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    // **the finger travels much further than the gap opens.** BouncingScrollPhysics damps an
    // overscroll the further past the edge it goes, so pulling 110px of finger yields nowhere near
    // 110px of extent - and it is the extent that _refreshTriggerDistance is measured against.
    // Moved in steps with a pump between, which is also what a real drag delivers.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
    }

    // the gap is open and the indicator is in it - drawn *above* the search bar, in the space that
    // opened under the header
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getCenter(find.byType(CircularProgressIndicator)).dy,
      lessThan(tester.getTopLeft(find.byType(SearchAndLikeBar)).dy),
      reason:
          'the spinner belongs in the gap between the header and the search bar',
    );

    await gesture.up();
    await tester.pump();
    expect(
      repo.fetchCount,
      2,
      reason: 'letting go past the trigger has to actually refetch',
    );

    // and the gap closes again on its own, taking the spinner with it. pumped in steps rather than
    // settled: an indeterminate CircularProgressIndicator animates forever, so pumpAndSettle would
    // time out here rather than ever returning.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an unreachable backend says so and offers a retry', (
    tester,
  ) async {
    final strings = AppLocalizations(AppLanguage.ru);
    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(error: const SocketException('connection refused')),
    );

    // a kind, not the exception's text: what the reader gets is written copy, and
    // `connection refused` goes to the log. see AppLocalizations.loadErrorHintFor.
    expect(controller.failure, LoadFailure.network);
    // no plausible shops standing in for the ones we could not fetch - the failure is what is shown
    expect(controller.vipShops, isEmpty);
    expect(controller.bestOffers, isEmpty);

    // a *failure* still gets a block of its own, because that is the one thing the open places
    // cannot explain by themselves - and it is danger-coloured with a retry, not a friendly
    // "nothing here yet"
    expect(find.text(strings.homeLoadError), findsOneWidget);
    expect(find.text(strings.loadErrorHint), findsOneWidget);
    expect(find.text(strings.retryButtonShort), findsOneWidget);

    // **and it takes the screen rather than hanging off the end of the feed.** the block used to be
    // appended below the sections, so a failed load drew five empty VIP slots and fifteen empty
    // rows and then apologised underneath them - a screen that looks like it worked, with the retry
    // a full scroll away from the problem it answers.
    expect(find.text(strings.vipShops), findsNothing);
    expect(find.text(strings.bestOffersTitle), findsNothing);

    // **and the exception itself is nowhere on screen.** this line is the point of the test now: the
    // card used to render `e.toString()` as its subtitle, so a customer looking for cement was shown
    // `ClientException: Connection closed before full header was received, uri=https://…/api/home`.
    expect(find.text('connection refused'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  // **"Проверьте подключение" over a server that answered sends somebody off to fix a working phone**,
  // and the home screen is the first thing every session opens
  for (final (status, failure) in [
    (500, LoadFailure.server),
    (429, LoadFailure.busy),
  ]) {
    testWidgets('a $status from the server never blames the connection', (
      tester,
    ) async {
      final strings = AppLocalizations(AppLanguage.ru);
      final controller = await _pumpHome(
        tester,
        _FakeHomeRepository(error: ApiException(status)),
      );

      expect(controller.failure, failure);
      expect(find.text(strings.loadErrorHintFor(failure)), findsOneWidget);
      expect(find.text(strings.loadErrorHint), findsNothing);
    });
  }

  testWidgets('real shops fill the slots from the front, and nothing is invented', (
    tester,
  ) async {
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

  testWidgets('a category tile opens onto that category\'s products', (
    tester,
  ) async {
    final repo = _FakeHomeRepository(
      content: _content(
        offers: {
          ShopCategory.universal: [
            _shop(
              id: 2,
              name: 'Настоящий',
              priceTier: PriceTier.cheaper,
              differencePercent: 12,
              basketPrice: 4400000,
            ),
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

    // the card is found by its name: the grid draws a product photograph, not a glyph
    await tester.tap(find.text(AppLocalizations(AppLanguage.ru).categoryMixes));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryProductsScreen), findsOneWidget);
    // it asked the backend for the category that was tapped, and rendered what came back
    expect(repo.requestedCategory, ProductCategory.mixes);
    expect(find.text('Цемент М400, 50 кг'), findsOneWidget);
    expect(find.text('88 000 сум'), findsOneWidget);
    // the shop's name is on the tile - a price with no seller attached is not actionable
    expect(find.text('Смеси Оптом'), findsOneWidget);
  });

  // a button that opens ProductSearchScreen, not a field: no TextField on the feed is the half of the
  // keyboard fix that keeps it fixed.
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

  testWidgets('submitting the search field opens the results for what was typed', (
    tester,
  ) async {
    final repo = _FakeHomeRepository(
      content: _content(
        offers: {
          ShopCategory.universal: [
            _shop(
              id: 2,
              name: 'Настоящий',
              priceTier: PriceTier.cheaper,
              differencePercent: 12,
              basketPrice: 4400000,
            ),
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

  testWidgets(
    'a short page of results offers no "Ещё" and asks for nothing more',
    (tester) async {
      final repo = _FakeHomeRepository(
        content: _content(),
        searchResults: [for (var i = 1; i <= 7; i++) _lamp(i)],
      );
      await _pumpHome(tester, repo);

      await tester.tap(find.byType(SearchAndLikeBar));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'лампа');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ProductGrid), const Offset(0, -20000));
      await tester.pumpAndSettle();

      expect(find.text('Ещё'), findsNothing);
      expect(repo.requestedOffsets, [0]);
    },
  );

  testWidgets(
    'a full page offers "Ещё", which fetches from the rows held and ends on a short page',
    (tester) async {
      final repo = _FakeHomeRepository(
        content: _content(),
        searchResults: [for (var i = 1; i <= 130; i++) _lamp(i)],
      );
      await _pumpHome(tester, repo);

      await tester.tap(find.byType(SearchAndLikeBar));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'лампа');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Ещё'),
        1000,
        scrollable: find.descendant(
          of: find.byType(ProductGrid),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('Ещё'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ещё'));
      await tester.pumpAndSettle();

      expect(repo.requestedOffsets, [0, 100]);

      // thirty rows came back: the list is over, so the button goes and nothing more is asked
      await tester.drag(find.byType(ProductGrid), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.text('Ещё'), findsNothing);
      expect(find.text('Лампа 130'), findsOneWidget);
    },
  );

  testWidgets('a search with no three-letter word goes nowhere', (
    tester,
  ) async {
    // nothing for the search index to look up, so the server answers 400 - the app does not ask.
    final repo = _FakeHomeRepository(content: _content());
    await _pumpHome(tester, repo);

    await tester.tap(find.byType(SearchAndLikeBar));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'це');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repo.requestedQuery, isNull);
    // and the screen says why rather than swallowing the press
    expect(find.text('Нужно хотя бы одно слово от трёх букв.'), findsOneWidget);
  });

  test('a query is searchable once one of its words has three letters', () {
    // mirrors minSearchWordLen on the server: the longest word has to reach three
    expect(ProductSearchScreen.isSearchable('це'), isFalse);
    expect(ProductSearchScreen.isSearchable('м 4 кг'), isFalse);
    expect(ProductSearchScreen.isSearchable('  цем  '), isTrue);
    expect(ProductSearchScreen.isSearchable('пвс 2х1,5'), isTrue);
  });

  testWidgets('the category cards carry no shop counts', (tester) async {
    // they did briefly, and it cost a database aggregate on every home load to tell a customer
    // something they had not asked. a card is a way in, not a statistic.
    final strings = AppLocalizations(AppLanguage.ru);
    await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(
          offers: {
            ShopCategory.universal: [
              _shop(id: 2, name: 'Настоящий', basketPrice: 4400000),
            ],
          },
        ),
      ),
    );

    // the grid is the categories that have a product shot - the other four are behind the header's
    // "Все категории", which is the whole reason the pager went away.
    //
    // scoped to the grid: several product categories share a name with a *shop* category, and those
    // are on this same screen as the best-offers segments
    for (final category in PopularCategoriesGrid.photographed) {
      expect(
        find.descendant(
          of: find.byType(PopularCategoriesGrid),
          matching: find.text(category.label(strings)),
        ),
        findsOneWidget,
      );
    }
    // and no numeric badge anywhere on it
    for (final digit in ['0', '2', '3', '4', '7']) {
      expect(find.text(digit), findsNothing);
    }
  });

  // **every heading stays, whatever the database holds.** Five VIP placements exist as a product
  // whether or not anybody has bought one, so their empty slots say "available"; the four shop
  // categories exist whether or not anybody has finished pricing, so their segments say the same
  // thing about a ranking. Neither section is allowed to disappear when it is empty.
  testWidgets('the VIP section is drawn with nothing sold', (tester) async {
    final strings = AppLocalizations(AppLanguage.ru);

    final controller = await _pumpHome(
      tester,
      _FakeHomeRepository(
        content: _content(
          offers: {
            ShopCategory.universal: [
              _shop(id: 2, name: 'Единственный', basketPrice: 5000000),
            ],
          },
        ),
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
  testWidgets(
    'a category with no products opens onto an empty state, not a story',
    (tester) async {
      final strings = AppLocalizations(AppLanguage.ru);
      final repo = _FakeHomeRepository(
        content: _content(),
        categoryProducts: const [],
      );
      await _pumpHome(tester, repo);

      await tester.tap(find.text(strings.categoryMixes));
      await tester.pumpAndSettle();

      expect(repo.requestedCategory, ProductCategory.mixes);
      expect(find.text(strings.noProductsInCategory), findsOneWidget);
      expect(find.byType(ProductTile), findsNothing);
    },
  );
}
