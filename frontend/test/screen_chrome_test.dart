// The two pieces of screen chrome that can be in the widget tree and still paint nothing.
//
// **The checks are on measured geometry, not on a widget being findable.** a childless ColoredBox
// takes the smallest size its constraints allow and `AppBar.bottom` hands down *loose* ones, so a
// header piece can lay out 1px tall and 0px wide with nothing thrown and nothing failing. The same
// class of bug is a surface the colour of the page, or one with no height.
//
// The product card is the other shape: a fixed-height tile holding a two-line name, a price, a shop
// line and a button at the narrowest width the app supports. Its failure is a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/core/widgets/pill_search_field.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/screens/product_results_screen.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/presentation/widgets/vip_shops_carousel.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

/// The narrowest tile the two-per-row grid ever builds: a 360dp phone, the grid's 16dp gutters and
/// its 12dp column gap.
const double _narrowestTile = (360 - 16 * 2 - 12) / 2;

final _strings = AppLocalizations(AppLanguage.ru);

Product _product({
  String name = 'Клей ПВА Эрон универсальный строительный',
  int? price = 14000,
  ProductAvailability availability = ProductAvailability.inStock,
  String specs = '',
}) {
  return Product(
    id: 1,
    shopId: 7,
    name: name,
    category: 'mixes',
    unit: 'кг',
    price: price,
    availability: availability,
    isTemplate: true,
    nameEditable: false,
    specs: specs,
  );
}

/// The header's own fill: the page's colour, so it sits flush instead of reading as a toolbar.
Finder _headerSurface() => find.descendant(
  of: find.byType(AppPageHeader),
  matching: find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == AppColors.background,
  ),
);

Future<Size> _pumpHeader(WidgetTester tester, AppPageHeader header) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(backgroundColor: AppColors.background, appBar: header),
    ),
  );
  return tester.getSize(_headerSurface());
}

void main() {
  group('the page header', () {
    testWidgets('spans the full width of the screen and carries no divider', (
      tester,
    ) async {
      final size = await _pumpHeader(
        tester,
        const AppPageHeader(title: 'Мои магазины'),
      );

      expect(
        size.width,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
      expect(size.height, greaterThan(40));
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == AppColors.textFaint,
        ),
        findsNothing,
      );
    });

    testWidgets('sits flush on the page: its own colour, no shadow of its own', (
      tester,
    ) async {
      await _pumpHeader(tester, const AppPageHeader(title: 'Мои магазины'));

      // a band of a second colour with a shadow under it is what read as a toolbar bolted on: the
      // only decorated box left in a title-only header is the back disc
      expect(
        find.descendant(
          of: find.byType(AppPageHeader),
          matching: find.byType(DecoratedBox),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is exactly as tall with a subtitle as without one', (
      tester,
    ) async {
      final plain = await _pumpHeader(
        tester,
        const AppPageHeader(title: 'Заявки'),
      );
      final withSubtitle = await _pumpHeader(
        tester,
        const AppPageHeader(title: 'Заявки', subtitle: 'Ваши заявки мастерам'),
      );

      // the row is a fixed height rather than an intrinsic one precisely so two tabs beside each
      // other cannot disagree about where the content starts
      expect(withSubtitle.height, plain.height);
    });

    testWidgets('and its two ends are the same control at the same size', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        AppPageHeader(
          title: 'Мои магазины',
          action: CircleIconButton(icon: Icons.add, onTap: () {}),
        ),
      );

      final discs = tester.widgetList<CircleIconButton>(
        find.byType(CircleIconButton),
      );
      expect(discs.length, 2);
      final sizes = find
          .byType(CircleIconButton)
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)));
      expect(sizes.toSet().length, 1);
    });

    testWidgets(
      'and a header carrying a search field sizes its discs to the field',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppPageHeader.custom(
                action: CircleIconButton(
                  icon: Icons.close_rounded,
                  diameter: AppPageHeader.customDisc,
                  onTap: () {},
                ),
                child: PillSearchField(controller: controller, hint: 'Поиск'),
              ),
            ),
          ),
        );

        final field = tester.getSize(find.byType(PillSearchField));
        for (final disc in find.byType(CircleIconButton).evaluate()) {
          expect(
            tester.getSize(find.byWidget(disc.widget)).height,
            field.height,
            // a disc 8px shorter than the capsule beside it reads as the lesser half of the bar,
            // which is what the search screen's back button looked like
            reason: 'a disc beside a search field is that field\'s height',
          );
        }
      },
    );
  });

  group('the product card', () {
    Future<void> pumpTile(WidgetTester tester, {required Widget tile}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _narrowestTile,
                height: ProductTile.height,
                child: tile,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'fits a long name, the description, a price and a shop at the narrowest width',
      (tester) async {
        await pumpTile(
          tester,
          tile: ProductTile(
            product: _product(
              specs: 'Оригинальный · Иран · Эрон · 1 кг · Белый · Для дерева',
            ),
            strings: _strings,
            subtitle: 'Qurilish Baza',
            showBuyerActions: true,
          ),
        );

        // a fixed-height tile that does not fit its content overflows rather than scrolling
        expect(tester.takeException(), isNull);
        expect(find.text('В наличии'), findsOneWidget);
        expect(find.text('Qurilish Baza'), findsOneWidget);
        expect(find.textContaining('Оригинальный · Иран'), findsOneWidget);
        expect(find.text('/ кг'), findsOneWidget);
      },
    );

    testWidgets(
      'states its availability on every tile, not only the awkward ones',
      (tester) async {
        for (final (availability, label) in [
          (ProductAvailability.inStock, 'В наличии'),
          (ProductAvailability.onOrder, 'Под заказ'),
          (ProductAvailability.unavailable, 'Нет в наличии'),
        ]) {
          await pumpTile(
            tester,
            tile: ProductTile(
              product: _product(availability: availability),
              strings: _strings,
            ),
          );
          expect(find.text(label), findsOneWidget, reason: 'for $availability');
        }
      },
    );

    testWidgets('keeps the heart off the owner\'s own grid', (tester) async {
      await pumpTile(
        tester,
        tile: ProductTile(
          product: _product(),
          strings: _strings,
          showOwnBadge: true,
        ),
      );

      expect(tester.takeException(), isNull);
      // the owner is not shopping in their own catalogue
      expect(
        find.bySemanticsLabel(_strings.addToFavouritesLabel),
        findsNothing,
      );
    });

    testWidgets(
      'an unpriced product still fits, with the prompt where the price goes',
      (tester) async {
        await pumpTile(
          tester,
          tile: ProductTile(
            product: _product(price: null),
            strings: _strings,
            subtitle: 'Дом Строй',
            showBuyerActions: true,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text(_strings.priceNotSet), findsOneWidget);
      },
    );
  });

  /// The filter field is not on the header until it is asked for - see ProductResultsScreen.
  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-search')));
    await tester.pumpAndSettle();
  }

  group('the category filter', () {
    CategoryProduct entry(String name, String shop) => CategoryProduct(
      product: _product(name: name),
      shopName: shop,
    );

    final catalogue = [
      entry('Клей ПВА Эрон', 'Qurilish Baza'),
      entry('Клей плиточный Ceresit', 'Дом Строй'),
      entry('Цемент М400', 'Qurilish Baza'),
    ];

    Future<void> pumpCategory(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            // the hearts on the grid read it; nothing here taps one
            ChangeNotifierProvider(create: (_) => FavoritesController()),
          ],
          child: MaterialApp(
            home: ProductResultsScreen(
              title: 'Смеси',
              load: () async => catalogue,
              emptyIcon: LucideIcons.container,
              emptyTitle: 'пусто',
              emptyHint: 'пока ничего',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('narrows the loaded list as it is typed, without refetching', (
      tester,
    ) async {
      var loads = 0;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            // the hearts on the grid read it; nothing here taps one
            ChangeNotifierProvider(create: (_) => FavoritesController()),
          ],
          child: MaterialApp(
            home: ProductResultsScreen(
              title: 'Смеси',
              load: () async {
                loads++;
                return catalogue;
              },
              emptyIcon: LucideIcons.container,
              emptyTitle: 'пусто',
              emptyHint: 'пока ничего',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Цемент М400'), findsOneWidget);

      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'клей');
      await tester.pumpAndSettle();

      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Цемент М400'), findsNothing);
      // the whole point: typing walks a list already in memory
      expect(loads, 1, reason: 'the filter must not refetch');
    });

    testWidgets('matches every word in any order, and matches the shop too', (
      tester,
    ) async {
      await pumpCategory(tester);
      await openSearch(tester);

      await tester.enterText(find.byType(TextField), 'эрон клей');
      await tester.pumpAndSettle();
      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Клей плиточный Ceresit'), findsNothing);

      // narrowing to one seller is the other thing a cross-shop filter is for
      await tester.enterText(find.byType(TextField), 'дом строй');
      await tester.pumpAndSettle();
      expect(find.text('Клей плиточный Ceresit'), findsOneWidget);
      expect(find.text('Клей ПВА Эрон'), findsNothing);
    });

    testWidgets('says the filter found nothing, not that the category is bare', (
      tester,
    ) async {
      await pumpCategory(tester);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'ламинат');
      await tester.pumpAndSettle();

      expect(find.text(_strings.categoryFilterNoResults), findsOneWidget);
      // the category's own empty wording would be a different, false claim here
      expect(find.text('пусто'), findsNothing);
    });

    testWidgets('the count in the header follows what is on screen', (
      tester,
    ) async {
      await pumpCategory(tester);
      expect(find.text(_strings.productsCountLabel(3)), findsOneWidget);

      // opening the search gives the field the title's place, and the count goes with the title -
      // the narrowed list is its own answer while somebody is typing at it
      await openSearch(tester);
      expect(find.text(_strings.productsCountLabel(3)), findsNothing);

      await tester.enterText(find.byType(TextField), 'клей');
      await tester.pumpAndSettle();

      // and putting the field away brings back the title, the whole category and its count
      await tester.tap(find.byKey(const ValueKey('close-search')));
      await tester.pumpAndSettle();
      expect(find.text('Смеси'), findsOneWidget);
      expect(find.text('Цемент М400'), findsOneWidget);
      expect(find.text(_strings.productsCountLabel(3)), findsOneWidget);
    });

    testWidgets(
      'and there is no field on the header until the magnifier is tapped',
      (tester) async {
        await pumpCategory(tester);

        // the whole point of the magnifier: a category page opens saying which category it is
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Смеси'), findsOneWidget);

        await openSearch(tester);

        expect(find.byType(TextField), findsOneWidget);
        // the title has stepped aside rather than moved over
        expect(find.text('Смеси'), findsNothing);
      },
    );

    testWidgets('the magnifier becomes the field rather than being replaced by one', (
      tester,
    ) async {
      await pumpCategory(tester);
      await tester.tap(find.byKey(const ValueKey('open-search')));

      // mid-flight the capsule is neither a disc nor a full-width field, and the heading has
      // already gone. a frame that overflows or throws here is the morph laid out wrong.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.takeException(), isNull);
      expect(find.text('Смеси'), findsNothing);

      await tester.pumpAndSettle();
      // and it lands on the page gutter, at the height of the disc it grew out of
      final field = tester.getRect(find.byType(PillSearchField));
      expect(field.right, tester.getSize(find.byType(MaterialApp)).width - 16);
      expect(field.height, CircleIconButton.disc);
    });
  });

  group('searching from a category page', () {
    // the category holds mixes; the catalogue also holds wallpaper, which the category never returns
    final inCategory = [
      CategoryProduct(
        product: _product(name: 'Клей ПВА Эрон'),
        shopName: 'Qurilish Baza',
      ),
      CategoryProduct(
        product: _product(name: 'Цемент М400'),
        shopName: 'Дом Строй',
      ),
    ];
    final acrossCatalogue = [
      CategoryProduct(
        product: _product(name: 'Обои Erismann'),
        shopName: 'Обои Плюс',
      ),
    ];

    Future<void> pump(
      WidgetTester tester, {
      required List<String> searched,
      bool withSearch = true,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            // the hearts on the grid read it; nothing here taps one
            ChangeNotifierProvider(create: (_) => FavoritesController()),
          ],
          child: MaterialApp(
            home: ProductResultsScreen(
              title: 'Смеси',
              load: () async => inCategory,
              onSearch: withSearch
                  ? (q, _) async {
                      searched.add(q);
                      return acrossCatalogue;
                    }
                  : null,
              emptyIcon: LucideIcons.container,
              emptyTitle: 'пусто',
              emptyHint: 'пока ничего',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('typing narrows this category only, and costs no request', (
      tester,
    ) async {
      final searched = <String>[];
      await pump(tester, searched: searched);
      await openSearch(tester);

      await tester.enterText(find.byType(TextField), 'клей');
      await tester.pumpAndSettle();

      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Цемент М400'), findsNothing);
      expect(searched, isEmpty, reason: 'narrowing must not hit the api');
    });

    testWidgets(
      'the search key leaves the category and searches the whole catalogue',
      (tester) async {
        final searched = <String>[];
        await pump(tester, searched: searched);
        await openSearch(tester);

        await tester.enterText(find.byType(TextField), 'обои');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        expect(searched, ['обои']);
        // a product this category could never have returned is now on screen
        expect(find.text('Обои Erismann'), findsOneWidget);
        expect(find.text('Клей ПВА Эрон'), findsNothing);
        // and the header stops claiming these are Смеси
        expect(
          find.textContaining(_strings.searchAcrossCategories),
          findsOneWidget,
        );
      },
    );

    testWidgets('clearing drops back into the category', (tester) async {
      final searched = <String>[];
      await pump(tester, searched: searched);
      await openSearch(tester);

      await tester.enterText(find.byType(TextField), 'обои');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Обои Erismann'), findsOneWidget);

      // the search key already put the field away and titled the screen with the query, so the way
      // back into the category is the × that took the magnifier's place
      await tester.tap(find.byKey(const ValueKey('close-search')));
      await tester.pumpAndSettle();

      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Цемент М400'), findsOneWidget);
      expect(
        find.textContaining(_strings.searchAcrossCategories),
        findsNothing,
      );
    });

    testWidgets('a query under three characters does not spend a request', (
      tester,
    ) async {
      final searched = <String>[];
      await pump(tester, searched: searched);
      await openSearch(tester);

      await tester.enterText(find.byType(TextField), 'об');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        searched,
        isEmpty,
        reason: 'the server index cannot answer a two-letter word',
      );
    });

    testWidgets('an empty filter points at the search key as the way out', (
      tester,
    ) async {
      final searched = <String>[];
      await pump(tester, searched: searched);
      await openSearch(tester);

      await tester.enterText(find.byType(TextField), 'ламинат');
      await tester.pumpAndSettle();

      expect(find.text(_strings.categoryFilterNoResultsHint), findsOneWidget);
    });
  });

  // ─────────────────────── the VIP card, at its worst ───────────────────────
  //
  // the same shape and failure mode as the product tile: a fixed-height card holding a name, two
  // lines of address, the comparison and two figures at the narrowest width - with **nearly half the
  // width taken by the photograph**. adding a line to that card costs a raise of
  // [VipShopsCarousel.cardHeight], and widening the frame costs the comparison its last characters.
  group('the VIP card at 320dp', () {
    Future<void> pumpCard(WidgetTester tester, HomeShopPreview? slot) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: Center(child: VipShopsCarousel(slots: [slot])),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    HomeShopPreview sold() => HomeShopPreview.fromShop(
      const Shop(
        id: 1,
        // the longest real shop name and the longest real address shape: a street, a number,
        // a district and the city, which is exactly two lines
        name: 'Строительные материалы Бунёдкор',
        contactPhone: '+998901112233',
        address: 'Чорсу майдони, 42, Алмазар тумани, Тошкент шаҳри',
        category: ShopCategory.universal,
        latitude: 41.3,
        longitude: 69.2,
        priceTier: PriceTier.dearer,
        priceDifferencePercent: 17,
        basketPrice: 5600000,
        isVip: true,
        productCount: 1284,
      ),
    );

    testWidgets('a sold placement fits, down to the last line', (tester) async {
      await pumpCard(tester, sold());

      // the card is exactly as tall as it says it is: a Column inside one fails by overflowing,
      // which is silent in release
      final card = tester.getSize(find.byType(PressableScale).first);
      expect(card.height, VipShopsCarousel.cardHeight);

      expect(find.text('Строительные материалы Бунёдкор'), findsOneWidget);
      expect(find.text('1284'), findsOneWidget);
      expect(find.text(_strings.cardProductsCaption), findsOneWidget);
      // **there is no rating to show and none is invented**: no reviews table exists, so a real
      // shop draws a dash and only an unsold slot carries a number
      expect(find.text(_strings.noFigure), findsOneWidget);
      expect(find.text(_strings.priceTierDearer(17)), findsOneWidget);

      // **the bars fall because the shop is dearer.** colour is not the only channel on this badge
      // and neither is the sentence: the glyph is read first, so its direction has to agree with
      // the tier rather than being decoration that happens to sit beside it.
      expect(
        find.byIcon(LucideIcons.chart_no_axes_column_decreasing),
        findsOneWidget,
      );
      expect(
        find.byIcon(LucideIcons.chart_no_axes_column_increasing),
        findsNothing,
      );

      // and the storefront is the half of the card it was widened into. the frame is the only
      // ClipRRect inside a slot, and it fills the card's height between its 8dp of padding.
      final frame = tester.getSize(
        find
            .descendant(
              of: find.byType(PressableScale).first,
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(frame.height, VipShopsCarousel.cardHeight - 16);
      expect(
        frame.width,
        greaterThan(card.width * 0.4),
        reason: 'the storefront is back to being a thumbnail beside the words',
      );
    });

    testWidgets('an unsold slot fits too, and names its fields', (
      tester,
    ) async {
      await pumpCard(tester, null);

      expect(
        tester.getSize(find.byType(PressableScale).first).height,
        VipShopsCarousel.cardHeight,
      );
      expect(find.text(_strings.slotShopNameLabel), findsOneWidget);
      expect(find.text(_strings.slotAddressLabel), findsOneWidget);
      expect(find.text(_strings.slotComparisonLabel), findsOneWidget);
      // the one figure on the slot that is a value rather than a field name - it is part of what
      // the placement is being sold as
      expect(find.text(kSlotRating), findsOneWidget);
    });
  });
}
