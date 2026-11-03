// The category filter in "Лучшие предложения", its fixed slots, and the badge on its rows.
//
// Four rules, each silent when broken: the filter shows every shop category whatever the backend sent
// (including on an empty database), every segment is the same width whatever its label, a tab holds a
// fixed number of places whether or not shops earned them, and **the raw Basket Price Index never
// reaches a screen**. Pinned by rendering, because all four are about what a person sees.

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
  return HomeShopPreview.fromShop(
    Shop(
      id: name.hashCode,
      name: name,
      contactPhone: '+998901112233',
      address: 'Ташкент',
      category: ShopCategory.universal,
      latitude: 41.3,
      longitude: 69.2,
      priceTier: tier,
      priceDifferencePercent: percent,
      basketPrice: basket,
    ),
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
  // **the state the app launches in**: nobody has finished pricing a catalogue, so no category has a
  // ranking. It used to render nothing at all - the whole section vanished - and then, briefly,
  // fifteen open places with no strip above them. The strip is the section's axis rather than a
  // filter over what happens to exist, so it is drawn here too.
  testWidgets('an empty backend still draws every segment and every place', (
    tester,
  ) async {
    await _pump(tester, const []);

    expect(find.byType(EmptyShopRow), findsNWidgets(BestOffersList.slotCount));
    expect(find.byType(HomeShopRow), findsNothing);

    for (final category in ShopCategory.values) {
      expect(find.text(category.label(_strings)), findsOneWidget);
    }
  });

  // one populated category used to hide the control entirely, on the reasoning that a single
  // permanently-selected pill reads as broken. With a constant four segments that case no longer
  // exists - there is always something to switch to.
  testWidgets('one ranked category still draws all four segments', (
    tester,
  ) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [_shop('Единственный')],
      ),
    ]);

    for (final category in ShopCategory.values) {
      expect(find.text(category.label(_strings)), findsOneWidget);
    }
    // Универсальный is first in enum order, so the strip opens on the one that has a ranking
    expect(find.text('Единственный'), findsOneWidget);
    expect(
      find.byType(EmptyShopRow),
      findsNWidgets(BestOffersList.slotCount - 1),
    );
  });

  testWidgets('two categories draw tabs, and tapping one switches the list', (
    tester,
  ) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [_shop('Стройка')],
      ),
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

  testWidgets('four or fewer segments fill the width; more of them scroll', (
    tester,
  ) async {
    CategoryOffers group(ShopCategory c) =>
        CategoryOffers(category: c, shops: [_shop(c.code)]);

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

  // **the rule that reversed on 2026-08-20.** The backend omits a category with no ranking, and the
  // strip used to be built straight off that list - so the control gained and lost segments between
  // two refreshes, and a customer looking for обои was told nothing at all. An empty segment says
  // "no shop of this kind has finished pricing", which is the same thing the open places under it
  // say and is worth reading.
  testWidgets('a category the backend sent nothing for is still a segment', (
    tester,
  ) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [_shop('Стройка')],
      ),
      CategoryOffers(category: ShopCategory.wood, shops: [_shop('Доски')]),
    ]);

    expect(find.text('Сантехника'), findsOneWidget);
    expect(find.text('Обои'), findsOneWidget);

    // and it opens onto a full set of open places rather than a dead end
    await tester.tap(find.text('Сантехника'));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyShopRow), findsNWidgets(BestOffersList.slotCount));
    expect(find.byType(HomeShopRow), findsNothing);
  });

  testWidgets('the badge is words and a colour, never the index', (
    tester,
  ) async {
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
      expect(
        find.text(index),
        findsNothing,
        reason: 'the raw index leaked into the UI',
      );
    }
  });

  // a defensive case, not a reachable one: ListBestOffersInCategory inner-joins the index, and since
  // migration 000013 a basket price and a tier are produced together or not at all. what this pins
  // is that the row widget draws its two facts independently rather than assuming both - so a
  // backend that grows a third state doesn't take the section down with it.
  testWidgets('a row renders a price without a badge rather than breaking', (
    tester,
  ) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.wallpaper,
        shops: [_shop('Обои Люкс', basket: 2500000)],
      ),
    ]);

    // Обои is the fourth segment and the strip always opens on the first, so the row is reached by
    // tapping rather than by being the only thing sent
    await tester.tap(find.text('Обои'));
    await tester.pumpAndSettle();

    expect(find.text('2 500 000 сум'), findsOneWidget);
    // no *badge* on the one real row. the open places below it carry the badge's label, which is a
    // field name and not a comparison - hence the exact three sentences rather than "рынка".
    for (final badge in [
      'на 0% дешевле рынка',
      'Средняя цена по рынку',
      'на 0% дороже рынка',
    ]) {
      expect(find.text(badge), findsNothing);
    }
  });

  // ─────────────────────────── the slots ───────────────────────────

  // the ranking is the section's whole meaning, so the real shops occupy the top of the list in the
  // order the server sent them - the open places are the tail, never interleaved
  testWidgets('the real shops come first, in the order they arrived', (
    tester,
  ) async {
    await _pump(tester, [
      CategoryOffers(
        category: ShopCategory.universal,
        shops: [
          _shop('Дешёвый', basket: 4000000),
          _shop('Дорогой', basket: 6000000),
        ],
      ),
    ]);

    final rows = tester
        .widgetList<HomeShopRow>(find.byType(HomeShopRow))
        .toList();
    expect(rows.map((r) => r.shop.name).toList(), ['Дешёвый', 'Дорогой']);

    // and every open place sits below the last real one
    final lastReal = tester.getTopLeft(find.byType(HomeShopRow).last).dy;
    final firstEmpty = tester.getTopLeft(find.byType(EmptyShopRow).first).dy;
    expect(firstEmpty, greaterThan(lastReal));
  });

  // never truncates. the count is a design constant and the server's LIMIT is what it mirrors, so
  // the two disagreeing must cost an extra row rather than hide a shop that earned its place.
  testWidgets('more shops than places grows the list instead of dropping any', (
    tester,
  ) async {
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
