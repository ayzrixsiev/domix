// Two things the map decides for itself, both silent when they break.
//
// **The zoom decides how a shop is drawn, never whether it is drawn.** a wrong threshold still
// renders, still pans and still looks like a working map: too high and the city is permanently
// anonymous dots, too low and seventy labelled pins overlap into noise on the first frame.
//
// **A price label may not appear on a pin MapKit is still shrinking.** the label is 13px type and
// the scale applies to the whole marker, so a label brought in below ShopPinIcon.fullScaleZoom is
// rendered at a size nothing recovers - and it looks like a label that is merely small.
//
// **The category chips are a filter over the same list** - one that filtered nothing, or could not be
// un-picked, would also just look like a map.
//
// It drives the camera through `DomixMap.onZoomChanged` rather than a pinch, because a synthesized
// gesture tests MapKit's gesture handling rather than ours, and asserts on `DomixMap.pins` rather
// than on widgets: **MapKit rasterizes a pin off-screen, so a ShopMarker is never mounted** and
// `find.byType` would report nothing at any zoom - passing for the wrong reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/presentation/screens/map_screen.dart';
import 'package:frontend/features/map/presentation/widgets/domix_map.dart';
import 'package:frontend/features/map/presentation/widgets/shop_marker.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/stores_repository.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';

// three shops around the middle of Tashkent, so they all fall inside the viewport at every zoom
// this test uses - otherwise MapKit's own off-screen culling would be what the assertions were
// measuring, rather than the threshold. two kinds, so the chips have something to tell apart.
const _categories = [
  ShopCategory.universal,
  ShopCategory.universal,
  ShopCategory.plumbing,
];

/// Priced, so the pins have a label to withhold - a shop without a tier draws the same key either
/// side of the threshold and would pass the label test for the wrong reason.
const _tier = PriceTier.cheaper;

class _FakeStoresRepository extends StoresRepository {
  @override
  Future<List<Shop>> fetchStores() async => [
    for (var i = 0; i < _categories.length; i++)
      Shop(
        id: i + 1,
        name: 'Магазин ${i + 1}',
        contactPhone: '+998901234567',
        address: 'Ташкент',
        category: _categories[i],
        latitude: 41.2995 + i * 0.001,
        longitude: 69.2401 + i * 0.001,
        priceTier: _tier,
        priceDifferencePercent: 12,
      ),
  ];
}

Future<StoresController> _pumpMap(WidgetTester tester) async {
  final stores = StoresController(repository: _FakeStoresRepository());

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider<StoresController>.value(value: stores),
        ChangeNotifierProvider(create: (_) => ProductsController()),
      ],
      child: const MaterialApp(home: MapScreen()),
    ),
  );

  // MapScreen kicks its load off in a post-frame callback, so one pump builds the tree and the next
  // settles the fake fetch and the rebuild it notifies
  await tester.pump();
  await tester.pump();

  return stores;
}

DomixMap _map(WidgetTester tester) =>
    tester.widget<DomixMap>(find.byType(DomixMap));

List<MapPin> _pins(WidgetTester tester) => _map(tester).pins;

/// MapKit reports every camera frame through this callback, programmatic moves included. Calling it
/// directly is the same thing a pinch would do, minus the gesture arena.
void _cameraAt(WidgetTester tester, double zoom) =>
    _map(tester).onZoomChanged!(zoom);

/// Taps a category chip and lets its animation settle.
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the map opens zoomed out, every shop drawn as a dot', (
    tester,
  ) async {
    final stores = await _pumpMap(tester);

    expect(
      stores.stores,
      hasLength(3),
      reason: 'the fake repository should have loaded',
    );
    expect(
      _pins(tester).map((pin) => pin.visualKey),
      everyElement(ShopDot.visualKey),
      reason:
          'at the opening zoom a shop is a dot - withholding the pins entirely is the bug this '
          'replaced, since where the shops are is what a city-wide map is for',
    );
  });

  testWidgets('zooming in turns the dots into full pins, and out again', (
    tester,
  ) async {
    await _pumpMap(tester);

    _cameraAt(tester, 14);
    await tester.pump();

    expect(_pins(tester), hasLength(3));
    expect(
      _pins(tester).any((pin) => pin.visualKey == ShopDot.visualKey),
      isFalse,
      reason:
          'zoomed in, every shop carries its own category and price in its key',
    );

    _cameraAt(tester, 10);
    await tester.pump();

    expect(_pins(tester), hasLength(3));
    expect(
      _pins(tester).map((pin) => pin.visualKey),
      everyElement(ShopDot.visualKey),
    );
  });

  testWidgets('the threshold sits above the zoom the map opens at', (
    tester,
  ) async {
    // the two constants are private, so this checks the property they exist to produce rather than
    // the numbers: at whatever zoom the map opens, shops are dots, and there is some zoom short of
    // the search fly-to that brings the detail in. a change that labels every pin on the first frame
    // removes the feature without breaking anything else.
    await _pumpMap(tester);
    expect(_pins(tester).first.visualKey, ShopDot.visualKey);

    _cameraAt(tester, 13);
    await tester.pump();
    expect(
      _pins(tester).first.visualKey,
      isNot(ShopDot.visualKey),
      reason:
          'one zoom step in from the city view should already read as pins - a threshold set '
          'higher leaves the map a field of dots for anyone who does not pinch several times',
    );
  });

  testWidgets('the price label waits until the pin has stopped being scaled down', (
    tester,
  ) async {
    await _pumpMap(tester);

    // the pin arrives first, with the comparison still held back
    _cameraAt(tester, ShopPinIcon.detailZoom);
    await tester.pump();
    expect(_pins(tester).first.visualKey, isNot(contains(_tier.name)));
    expect(ShopPinIcon.scaleForZoom(ShopPinIcon.detailZoom), lessThan(1));

    _cameraAt(tester, ShopPinIcon.fullScaleZoom);
    await tester.pump();
    expect(
      _pins(tester).first.visualKey,
      contains(_tier.name),
      reason:
          'by full size the pin has room for the comparison, which is the whole point of a '
          'labelled pin',
    );
    expect(
      ShopPinIcon.scaleForZoom(ShopPinIcon.fullScaleZoom),
      1,
      reason:
          'the label appears at the zoom the pin stops shrinking at - bringing it in any '
          'earlier renders 13px type at a fraction of its size',
    );
  });

  testWidgets(
    'a category chip leaves only its own shops, and un-picks on a second tap',
    (tester) async {
      await _pumpMap(tester);

      await _tapChip(tester, 'Сантехника');
      expect(
        _pins(tester),
        hasLength(1),
        reason:
            'two of the three fakes are универсальный, so one plumbing shop should be left',
      );

      // the picked chip is the only way back to every shop - there is no «Все» chip to fall back on,
      // so a tap that did not un-pick would strand the user inside one category
      await _tapChip(tester, 'Сантехника');
      expect(_pins(tester), hasLength(3));
    },
  );

  testWidgets(
    'an empty category says so, rather than looking like an empty city',
    (tester) async {
      await _pumpMap(tester);

      await _tapChip(tester, 'Обои');
      expect(_pins(tester), isEmpty);
      expect(find.text('В этой категории пока нет магазинов'), findsOneWidget);
      expect(find.text('Пока нет магазинов'), findsNothing);
    },
  );
}
