// Two things the map decides for itself, both silent when they break.
//
// **The zoom decides how a shop is drawn, never whether it is drawn.** Below MapScreen's threshold
// a shop is a dot, above it a full teardrop with its category glyph and its price label. Get the
// threshold wrong in either direction and the screen still renders, still pans, still looks like a
// working map: set it above every zoom a user reaches and the city is permanently a scatter of
// anonymous dots; set it below the opening zoom and seventy labelled pins overlap into noise on the
// first frame. Nothing crashes, so nothing tells you.
//
// **The category chips are a filter over the same list.** A chip that filtered nothing, or one that
// could not be un-picked, would also just look like a map.
//
// It drives the camera through `DomixMap.onZoomChanged` rather than through a pinch gesture. A
// synthesized gesture would be testing MapKit's native gesture handling, which is not ours; the
// contract that *is* ours is "given a camera at this zoom, hand the map these pins", and that
// callback is exactly where the two meet.
//
// It also asserts on `DomixMap.pins` rather than on ShopMarker widgets in the tree, and that is
// forced rather than chosen: MapKit rasterizes a pin off-screen and draws the bitmap natively, so a
// ShopMarker is never mounted and `find.byType` would report nothing at any zoom - the test would
// pass for the wrong reason. The list of MapPins is the last thing on our side of the boundary,
// which makes it the right thing to check.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/presentation/screens/map_screen.dart';
import 'package:frontend/features/map/presentation/widgets/domix_map.dart';
import 'package:frontend/features/map/presentation/widgets/shop_marker.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
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

DomixMap _map(WidgetTester tester) => tester.widget<DomixMap>(find.byType(DomixMap));

List<MapPin> _pins(WidgetTester tester) => _map(tester).pins;

/// MapKit reports every camera frame through this callback, programmatic moves included. Calling it
/// directly is the same thing a pinch would do, minus the gesture arena.
void _cameraAt(WidgetTester tester, double zoom) => _map(tester).onZoomChanged!(zoom);

/// Taps a category chip and lets its animation settle.
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the map opens zoomed out, every shop drawn as a dot', (tester) async {
    final stores = await _pumpMap(tester);

    expect(stores.stores, hasLength(3), reason: 'the fake repository should have loaded');
    expect(
      _pins(tester).map((pin) => pin.visualKey),
      everyElement(ShopDot.visualKey),
      reason: 'at the opening zoom a shop is a dot - withholding the pins entirely is the bug this '
          'replaced, since where the shops are is what a city-wide map is for',
    );
  });

  testWidgets('zooming in turns the dots into full pins, and out again', (tester) async {
    await _pumpMap(tester);

    _cameraAt(tester, 14);
    await tester.pump();

    expect(_pins(tester), hasLength(3));
    expect(
      _pins(tester).any((pin) => pin.visualKey == ShopDot.visualKey),
      isFalse,
      reason: 'zoomed in, every shop carries its own category and price in its key',
    );

    _cameraAt(tester, 10);
    await tester.pump();

    expect(_pins(tester), hasLength(3));
    expect(_pins(tester).map((pin) => pin.visualKey), everyElement(ShopDot.visualKey));
  });

  testWidgets('the threshold sits above the zoom the map opens at', (tester) async {
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
      reason: 'one zoom step in from the city view should already read as pins - a threshold set '
          'higher leaves the map a field of dots for anyone who does not pinch several times',
    );
  });

  testWidgets('a category chip leaves only its own shops, and un-picks on a second tap',
      (tester) async {
    await _pumpMap(tester);

    await _tapChip(tester, 'Сантехника');
    expect(
      _pins(tester),
      hasLength(1),
      reason: 'two of the three fakes are универсальный, so one plumbing shop should be left',
    );

    // the picked chip is the only way back to every shop - there is no «Все» chip to fall back on,
    // so a tap that did not un-pick would strand the user inside one category
    await _tapChip(tester, 'Сантехника');
    expect(_pins(tester), hasLength(3));
  });

  testWidgets('an empty category says so, rather than looking like an empty city', (tester) async {
    await _pumpMap(tester);

    await _tapChip(tester, 'Обои');
    expect(_pins(tester), isEmpty);
    expect(find.text('В этой категории пока нет магазинов'), findsOneWidget);
    expect(find.text('Пока нет магазинов'), findsNothing);
  });
}
