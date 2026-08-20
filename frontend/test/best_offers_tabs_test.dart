// The category filter in "Лучшие предложения", its fixed slots, and the badge on its rows.
//
// Four rules here are easy to break by accident and silent when broken: the filter must not appear
// for a single category (the state the app launches in), every segment must be the same width
// whatever its label, the tab must hold a fixed number of places whether or not shops have earned
// them, and the raw Basket Price Index must never reach a screen. All four are pinned by rendering
// rather than by reading the widget, because all four are about what a person sees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/home/presentation/widgets/home_shop_row.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';

final _strings = AppLocalizations(AppLanguage.ru);

// built through the real projection rather than a bare constructor: every preview in the app comes
// from a backend row now (the invented-shop file is gone), and a fixture that could not have arrived
// that way would be testing a shape the app cannot produce.
HomeShopPreview _shop(
  String name, {
  PriceTier? tier,
  int? percent,
  int? basket = 5000000,
}) {
  return HomeShopPreview.fromShop(Shop(
    id: name.hashCode,
    name: name,
    contactPhone: '+998901112233',
    address: 'Ташкент',
    category: ShopCategory.universal,
    latitude: 41.3,
    longitude: 69.2,
    rating: 4.5,
    priceTier: tier,
    priceDifferencePercent: percent,
    basketPrice: basket,
  ));
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
  // **the state the app launches in**, and it used to render nothing at all - the section vanished,
  // which read as a screen missing a chunk of itself rather than as a ranking with room in it.
  testWidgets('no ranked category still draws its places, with no tab strip', (tester) async {
    await _pump(tester, const []);

    expect(find.byType(EmptyShopRow), findsNWidgets(BestOffersList.slotCount));
    expect(find.byType(HomeShopRow), findsNothing);

    // no strip, because the tabs come from the data and there is none. a tab set to no category
    // would be a filter that filters to nothing.
    for (final label in ['Универсальный', 'Сантехника', 'Обои']) {
      expect(find.text(label), findsNothing);
    }
  });

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
    // no *badge* on the one real row. the open places below it carry the badge's label, which is a
    // field name and not a comparison - hence the exact three sentences rather than "рынка".
    for (final badge in ['на 0% дешевле рынка', 'Средняя цена по рынку', 'на 0% дороже рынка']) {
      expect(find.text(badge), findsNothing);
    }
  });

  // ─────────────────────────── the slots ───────────────────────────

  // **the tab is a fixed number of places, not a list that shrinks to its contents.** what an owner
  // reads off two shops and thirteen open rows is "this category is not full and finishing my prices
  // puts me in it", which is the one message that reaches somebody stuck halfway through pricing -
  // in the place they are most likely to be looking.
  testWidgets('a tab always holds its full number of places', (tester) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [_shop('Первый', basket: 4000000), _shop('Второй', basket: 4500000)],
      ),
    ]);

    expect(find.byType(HomeShopRow), findsNWidgets(2));
    expect(find.byType(EmptyShopRow), findsNWidgets(BestOffersList.slotCount - 2));
  });

  // the ranking is the section's whole meaning, so the real shops occupy the top of the list in the
  // order the server sent them - the open places are the tail, never interleaved
  testWidgets('the real shops come first, in the order they arrived', (tester) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [_shop('Дешёвый', basket: 4000000), _shop('Дорогой', basket: 6000000)],
      ),
    ]);

    final rows = tester.widgetList<HomeShopRow>(find.byType(HomeShopRow)).toList();
    expect(rows.map((r) => r.shop.name).toList(), ['Дешёвый', 'Дорогой']);

    // and every open place sits below the last real one
    final lastReal = tester.getTopLeft(find.byType(HomeShopRow).last).dy;
    final firstEmpty = tester.getTopLeft(find.byType(EmptyShopRow).first).dy;
    expect(firstEmpty, greaterThan(lastReal));
  });

  // **no invented shop anywhere in an open place.** this is the section a customer decides where to
  // drive from, so a plausible-looking name or price in it would be the worst kind of wrong.
  testWidgets('an open place shows field names and no data', (tester) async {
    await _pump(tester, [
      CategoryOffers(category: ShopCategory.universal, shops: [_shop('Настоящий')]),
    ]);

    final empties = BestOffersList.slotCount - 1;
    expect(find.text(_strings.slotShopNameLabel), findsNWidgets(empties));
    expect(find.text(_strings.slotAddressLabel), findsNWidgets(empties));
    expect(find.text(_strings.slotBasketLabel), findsNWidgets(empties));
    expect(find.text(_strings.slotComparisonLabel), findsNWidgets(empties));
    // the one value an open place does show, and it is a description of the field rather than a
    // score anybody earned
    expect(find.text('5'), findsNWidgets(empties));

    // and nothing inside an open place that could be read as a real amount. scoped to the empty
    // rows on purpose - the real shop above them prints its basket, which is the whole point of it.
    expect(
      find.descendant(of: find.byType(EmptyShopRow), matching: find.textContaining('сум')),
      findsNothing,
    );
  });

  // never truncates. the count is a design constant and the server's LIMIT is what it mirrors, so
  // the two disagreeing must cost an extra row rather than hide a shop that earned its place.
  testWidgets('more shops than places grows the list instead of dropping any', (tester) async {
    final many = [
      for (var i = 0; i < BestOffersList.slotCount + 3; i++)
        _shop('Магазин $i', basket: 4000000 + i),
    ];
    await _pump(tester, [
      CategoryOffers(category: ShopCategory.universal, shops: many),
    ]);

    expect(find.byType(HomeShopRow), findsNWidgets(many.length));
    expect(find.byType(EmptyShopRow), findsNothing);
  });
}
