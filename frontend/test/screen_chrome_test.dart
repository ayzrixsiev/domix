// The two pieces of screen chrome that can be present in the widget tree and still paint nothing.
//
// The rule under a header is the reason this file exists. It was added to every pushed screen and
// was invisible on all of them: a childless ColoredBox takes the smallest size its constraints
// allow, and `AppBar.bottom` hands down *loose* ones, so it laid out 1px tall and 0px wide. Nothing
// threw, no test failed, and the only symptom was a header that looked exactly as it had before -
// which is why the check here is on measured width rather than on the widget being findable.
//
// The product card is the other shape: a fixed-height tile that has to hold a two-line name, a
// price, a shop line and a button at the narrowest width the app supports. Its failure mode is a
// RenderFlex overflow, which is loud in a test and a yellow stripe on a phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/screen_header.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/screens/product_results_screen.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

/// The narrowest tile the two-per-row grid ever builds: a 360dp phone, the grid's 16dp gutters and
/// its 12dp column gap.
const double _narrowestTile = (360 - 16 * 2 - 12) / 2;

final _strings = AppLocalizations(AppLanguage.ru);

Product _product({
  String name = 'Клей ПВА Эрон универсальный строительный',
  int? price = 14000,
  ProductAvailability availability = ProductAvailability.inStock,
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
  );
}

Finder _ruleFinder() => find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == AppColors.textFaint,
    );

void main() {
  group('the header rule', () {
    testWidgets('spans the app bar it is given to, rather than collapsing to nothing',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Смеси'), bottom: ScreenHeader.appBarRule()),
        ),
      ));

      final size = tester.getSize(_ruleFinder());
      expect(size.height, 1);
      // the real assertion. it was 0 here, and every other check still passed.
      expect(size.width, greaterThan(200));
    });

    testWidgets('and inside a ScreenHeader, where the Column already stretches it', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ScreenHeader(title: 'Сообщения', subtitle: 'Ваши переписки'),
        ),
      ));

      expect(tester.getSize(_ruleFinder()).width, greaterThan(200));
    });

    testWidgets('and is gone when a screen has its own structure under the title', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ScreenHeader(title: 'Заявки', subtitle: 'Шаг 1', showRule: false),
        ),
      ));

      expect(_ruleFinder(), findsNothing);
    });
  });

  group('the product card', () {
    Future<void> pumpTile(WidgetTester tester, {required Widget tile}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: _narrowestTile, height: ProductTile.height, child: tile),
          ),
        ),
      ));
    }

    testWidgets('fits a long name, a price, a shop and both buttons at the narrowest width',
        (tester) async {
      await pumpTile(
        tester,
        tile: ProductTile(
          product: _product(),
          strings: _strings,
          subtitle: 'Qurilish Baza',
          showBuyerActions: true,
        ),
      );

      // a fixed-height tile that does not fit its content overflows rather than scrolling
      expect(tester.takeException(), isNull);
      expect(find.text('В наличии'), findsOneWidget);
      expect(find.text('Qurilish Baza'), findsOneWidget);
      expect(find.text('/ кг'), findsOneWidget);
    });

    testWidgets('states its availability on every tile, not only the awkward ones', (tester) async {
      for (final (availability, label) in [
        (ProductAvailability.inStock, 'В наличии'),
        (ProductAvailability.onOrder, 'Под заказ'),
        (ProductAvailability.unavailable, 'Нет в наличии'),
      ]) {
        await pumpTile(
          tester,
          tile: ProductTile(product: _product(availability: availability), strings: _strings),
        );
        expect(find.text(label), findsOneWidget, reason: 'for $availability');
      }
    });

    testWidgets('keeps the shopper buttons off the owner\'s own grid', (tester) async {
      await pumpTile(
        tester,
        tile: ProductTile(product: _product(), strings: _strings, showOwnBadge: true),
      );

      expect(tester.takeException(), isNull);
      // the owner is not shopping in their own catalogue
      expect(find.bySemanticsLabel(_strings.addToBasketLabel), findsNothing);
      expect(find.bySemanticsLabel(_strings.addToFavouritesLabel), findsNothing);
    });

    testWidgets('an unpriced product still fits, with the prompt where the price goes',
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
    });
  });

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
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
        child: MaterialApp(
          home: ProductResultsScreen(
            title: 'Смеси',
            load: () async => catalogue,
            emptyIcon: LucideIcons.container,
            emptyTitle: 'пусто',
            emptyHint: 'пока ничего',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('narrows the loaded list as it is typed, without refetching', (tester) async {
      var loads = 0;
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
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
      ));
      await tester.pumpAndSettle();
      expect(find.text('Цемент М400'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'клей');
      await tester.pumpAndSettle();

      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Цемент М400'), findsNothing);
      // the whole point: typing walks a list already in memory
      expect(loads, 1, reason: 'the filter must not refetch');
    });

    testWidgets('matches every word in any order, and matches the shop too', (tester) async {
      await pumpCategory(tester);

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

    testWidgets('says the filter found nothing, not that the category is bare', (tester) async {
      await pumpCategory(tester);
      await tester.enterText(find.byType(TextField), 'ламинат');
      await tester.pumpAndSettle();

      expect(find.text(_strings.categoryFilterNoResults), findsOneWidget);
      // the category's own empty wording would be a different, false claim here
      expect(find.text('пусто'), findsNothing);
    });

    testWidgets('the count in the header follows what is on screen', (tester) async {
      await pumpCategory(tester);
      expect(find.text(_strings.productsCountLabel(3)), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'клей');
      await tester.pumpAndSettle();
      expect(find.text(_strings.productsCountLabel(2)), findsOneWidget);
    });
  });

  group('searching from a category page', () {
    // the category holds mixes; the catalogue also holds wallpaper, which the category never returns
    final inCategory = [
      CategoryProduct(product: _product(name: 'Клей ПВА Эрон'), shopName: 'Qurilish Baza'),
      CategoryProduct(product: _product(name: 'Цемент М400'), shopName: 'Дом Строй'),
    ];
    final acrossCatalogue = [
      CategoryProduct(product: _product(name: 'Обои Erismann'), shopName: 'Обои Плюс'),
    ];

    Future<void> pump(
      WidgetTester tester, {
      required List<String> searched,
      bool withSearch = true,
    }) async {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
        child: MaterialApp(
          home: ProductResultsScreen(
            title: 'Смеси',
            load: () async => inCategory,
            onSearch: withSearch
                ? (q) async {
                    searched.add(q);
                    return acrossCatalogue;
                  }
                : null,
            emptyIcon: LucideIcons.container,
            emptyTitle: 'пусто',
            emptyHint: 'пока ничего',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('typing narrows this category only, and costs no request', (tester) async {
      final searched = <String>[];
      await pump(tester, searched: searched);

      await tester.enterText(find.byType(TextField), 'клей');
      await tester.pumpAndSettle();

      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Цемент М400'), findsNothing);
      expect(searched, isEmpty, reason: 'narrowing must not hit the api');
    });

    testWidgets('the search key leaves the category and searches the whole catalogue',
        (tester) async {
      final searched = <String>[];
      await pump(tester, searched: searched);

      await tester.enterText(find.byType(TextField), 'обои');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(searched, ['обои']);
      // a product this category could never have returned is now on screen
      expect(find.text('Обои Erismann'), findsOneWidget);
      expect(find.text('Клей ПВА Эрон'), findsNothing);
      // and the header stops claiming these are Смеси
      expect(find.textContaining(_strings.searchAcrossCategories), findsOneWidget);
    });

    testWidgets('clearing drops back into the category', (tester) async {
      final searched = <String>[];
      await pump(tester, searched: searched);

      await tester.enterText(find.byType(TextField), 'обои');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Обои Erismann'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Клей ПВА Эрон'), findsOneWidget);
      expect(find.text('Цемент М400'), findsOneWidget);
      expect(find.textContaining(_strings.searchAcrossCategories), findsNothing);
    });

    testWidgets('a query under three characters does not spend a request', (tester) async {
      final searched = <String>[];
      await pump(tester, searched: searched);

      await tester.enterText(find.byType(TextField), 'об');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(searched, isEmpty, reason: 'the server index cannot answer a two-letter word');
    });

    testWidgets('an empty filter points at the search key as the way out', (tester) async {
      final searched = <String>[];
      await pump(tester, searched: searched);

      await tester.enterText(find.byType(TextField), 'ламинат');
      await tester.pumpAndSettle();

      expect(find.text(_strings.categoryFilterNoResultsHint), findsOneWidget);
    });
  });
}
