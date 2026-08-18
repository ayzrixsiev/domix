// Shop pins are withheld until the map is zoomed in past MapScreen._minShopZoom.
//
// This is pinned by a test because both ways of getting it wrong are silent. Raise the threshold
// above any zoom a user reaches and the map is permanently empty; drop it below the initial zoom and
// the feature never fires at all - and either way the screen still renders, still scrolls, still
// looks like a working map. Nothing crashes, so nothing tells you.
//
// It drives the camera through `DomixMap.onZoomChanged` rather than through a pinch gesture. A
// synthesized gesture would be testing MapKit's native gesture handling, which is not ours; the
// contract that *is* ours is "given a camera at this zoom, hand the map pins or don't", and that
// callback is exactly where the two meet.
//
// It also asserts on `DomixMap.pins` rather than on ShopMarker widgets in the tree, and that is
// forced rather than chosen: MapKit rasterizes a pin off-screen and draws the bitmap natively, so a
// ShopMarker is never mounted and `find.byType` would report nothing at any zoom - the test would
// pass for the wrong reason at zoom 12 and fail for the wrong reason at 14. The list of MapPins is
// the last thing on our side of the boundary, which makes it the right thing to check.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/presentation/screens/map_screen.dart';
import 'package:frontend/features/map/presentation/widgets/domix_map.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/stores_repository.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';

// three shops around the middle of Tashkent, so they all fall inside the viewport at every zoom
// this test uses - otherwise MapKit's own off-screen culling would be what the assertions were
// measuring, rather than the threshold
class _FakeStoresRepository extends StoresRepository {
  @override
  Future<List<Shop>> fetchStores() async => [
        for (var i = 0; i < 3; i++)
          Shop(
            id: i + 1,
            name: 'Магазин ${i + 1}',
            contactPhone: '+998901234567',
            address: 'Ташкент',
            category: ShopCategory.universal,
            latitude: 41.2995 + i * 0.001,
            longitude: 69.2401 + i * 0.001,
            rating: 4.5,
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

/// How many pins the screen is currently handing the map.
int _pinCount(WidgetTester tester) => _map(tester).pins.length;

/// MapKit reports every camera frame through this callback, programmatic moves included. Calling it
/// directly is the same thing a pinch would do, minus the gesture arena.
void _cameraAt(WidgetTester tester, double zoom) => _map(tester).onZoomChanged!(zoom);

void main() {
  testWidgets('the map opens zoomed out, with no pins and a line saying why', (tester) async {
    final stores = await _pumpMap(tester);

    expect(stores.stores, hasLength(3), reason: 'the fake repository should have loaded');
    expect(
      _pinCount(tester),
      0,
      reason: 'the initial zoom is below the threshold, so no pin should be drawn',
    );
    // and the reason is on screen - an empty map with no explanation reads as a broken app, and the
    // count is what separates "zoom in" from "this city has no shops"
    expect(find.textContaining('Приблизьте карту'), findsOneWidget);
    expect(find.textContaining('3 магазина'), findsOneWidget);
  });

  testWidgets('zooming in brings every shop back, and zooming out hides them again', (tester) async {
    await _pumpMap(tester);

    _cameraAt(tester, 14);
    await tester.pump();

    expect(_pinCount(tester), 3);
    expect(find.textContaining('Приблизьте карту'), findsNothing);

    _cameraAt(tester, 10);
    await tester.pump();

    expect(_pinCount(tester), 0);
    expect(find.textContaining('Приблизьте карту'), findsOneWidget);
  });

  testWidgets('the threshold sits above the zoom the map opens at', (tester) async {
    // the two constants are private, so this checks the property they exist to produce rather than
    // the numbers: at whatever zoom the map opens, pins are withheld, and there is some zoom short
    // of the search fly-to that brings them in. a change that makes the map open with every pin
    // drawn removes the feature without breaking anything else.
    await _pumpMap(tester);
    expect(_pinCount(tester), 0);

    _cameraAt(tester, 13);
    await tester.pump();
    expect(
      _pinCount(tester),
      3,
      reason: 'one zoom step in from the city view should already show shops - a threshold set '
          'higher than this leaves the map empty for anyone who does not pinch several times',
    );
  });
}
