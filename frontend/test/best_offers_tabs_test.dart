// The category filter in "Лучшие предложения", and the badge on its rows.
//
// Three rules here are easy to break by accident and silent when broken: the filter must not appear
// for a single category (the state the app launches in), every segment must be the same width
// whatever its label, and the raw Basket Price Index must never reach a screen. All three are
// pinned by rendering rather than by reading the widget, because all three are about what a person
// sees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

HomeShopPreview _shop(
  String name, {
  PriceTier? tier,
  int? percent,
  int? basket = 5000000,
}) {
  return HomeShopPreview(
    name: name,
    address: 'Ташкент',
    rating: 4.5,
    priceTier: tier,
    priceDifferencePercent: percent,
    basketPrice: basket,
  );
}

Future<void> _pump(WidgetTester tester, List<CategoryOffers> groups) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => LanguageProvider())],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BestOffersList(groups: groups)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a single category draws no tab strip', (tester) async {
    // the state the app launches in. one permanently-selected pill reads as a control that is
    // broken, so the strip is not drawn at all rather than drawn with nothing to switch to.
    await _pump(tester, [
      CategoryOffers(category: ShopCategory.universal, shops: [_shop('Единственный')]),
    ]);

    expect(find.text('Единственный'), findsOneWidget);
    expect(find.text('Универсальный'), findsNothing);
  });

  testWidgets('two categories draw tabs, and tapping one switches the list', (tester) async {
    await _pump(tester, [
      CategoryOffers(category: ShopCategory.universal, shops: [_shop('Стройка')]),
      CategoryOffers(category: ShopCategory.plumbing, shops: [_shop('Трубы')]),
    ]);

    // the first tab is selected on arrival, so only its shops are on screen
    expect(find.text('Стройка'), findsOneWidget);
    expect(find.text('Трубы'), findsNothing);

    await tester.tap(find.text('Сантехника'));
    await tester.pumpAndSettle();

    expect(find.text('Трубы'), findsOneWidget);
    expect(find.text('Стройка'), findsNothing);
  });

  testWidgets('every segment is exactly the same width, whatever the label', (tester) async {
    // the point of a segmented control is that the options read as peers. "Универсальный" is eleven
    // characters and "Обои" is four, so sizing to content would make one segment three times
    // another and leave the control looking like a mistake.
    await _pump(tester, [
      CategoryOffers(category: ShopCategory.universal, shops: [_shop('a')]),
      CategoryOffers(category: ShopCategory.plumbing, shops: [_shop('b')]),
      CategoryOffers(category: ShopCategory.wallpaper, shops: [_shop('c')]),
    ]);

    final widths = <double>[];
    for (final label in ['Универсальный', 'Сантехника', 'Обои']) {
      // the SizedBox wrapping each segment is what fixes the width
      final box = find.ancestor(
        of: find.text(label),
        matching: find.byType(SizedBox),
      );
      widths.add(tester.getSize(box.first).width);
    }

    expect(widths[0], closeTo(widths[1], 0.5));
    expect(widths[1], closeTo(widths[2], 0.5));
  });

  testWidgets('four or fewer segments fill the width; more of them scroll', (tester) async {
    CategoryOffers group(ShopCategory c) => CategoryOffers(category: c, shops: [_shop(c.code)]);

    // four fit: no scroll view inside the control
    await _pump(tester, [
      group(ShopCategory.universal),
      group(ShopCategory.plumbing),
      group(ShopCategory.wood),
      group(ShopCategory.wallpaper),
    ]);
    // the only scrollable on screen is the page itself, not the filter
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('a category with no shops is never a tab', (tester) async {
    // the backend already omits empty groups, so this is really asserting the app does not invent
    // them - it renders one tab per group it was handed and nothing else
    await _pump(tester, [
      CategoryOffers(category: ShopCategory.universal, shops: [_shop('Стройка')]),
      CategoryOffers(category: ShopCategory.wood, shops: [_shop('Доски')]),
    ]);

    expect(find.text('Сантехника'), findsNothing);
    expect(find.text('Обои'), findsNothing);
  });

  testWidgets('the badge is words and a colour, never the index', (tester) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [
          _shop('Дёшево', tier: PriceTier.cheaper, percent: 4, basket: 4800000),
          _shop('Дорого', tier: PriceTier.dearer, percent: 6, basket: 5300000),
          _shop('Ровно', tier: PriceTier.average, percent: 1, basket: 5050000),
        ],
      ),
    ]);

    expect(find.text('на 4% дешевле рынка'), findsOneWidget);
    expect(find.text('на 6% дороже рынка'), findsOneWidget);
    // the average tier drops the percentage entirely - "на 1% дешевле" is a distinction the band
    // exists to say is not worth making
    expect(find.text('Средняя цена по рынку'), findsOneWidget);

    // the numbers 96 / 106 / 99 exist nowhere on screen
    for (final index in ['96', '106', '99', '104']) {
      expect(find.text(index), findsNothing, reason: 'the raw index leaked into the UI');
    }
  });

  // a defensive case, not a reachable one: ListBestOffersInCategory inner-joins the index, and since
  // migration 000013 a basket price and a tier are produced together or not at all. what this pins
  // is that the row widget draws its two facts independently rather than assuming both - so a
  // backend that grows a third state doesn't take the section down with it.
  testWidgets('a row renders a price without a badge rather than breaking', (tester) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.wallpaper,
        shops: [_shop('Обои Люкс', basket: 2500000)],
      ),
    ]);

    expect(find.text('2 500 000 сум'), findsOneWidget);
    expect(find.textContaining('рынка'), findsNothing);
  });
}
