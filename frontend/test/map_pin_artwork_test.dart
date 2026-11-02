// The two things about the map's pin drawings that break without an error.
//
// **A pin whose point is not on the bottom row dead centre stands beside the shop.** Every file is
// padded so its lowest solid ink sits on the middle of the canvas and on its last row, which is
// what lets ShopMarker centre its column and every placemark anchor at (0.5, 1.0). Re-exporting one
// without rebuilding that moves the shop on the map and nothing complains.
//
// **A pin built before its file has decoded rasterizes blank.** MapKit paints the widget once,
// off-screen, and caches the bitmap - so ShopPinIcon.decoded has to leave the image in the cache
// for the next build to find synchronously, or the map shows empty space where a shop is.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/map/presentation/widgets/shop_marker.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The lowest solid ink in the drawing: its horizontal centre as a fraction of the width, and the
/// row it was found on.
Future<(double, int)> _tipCentre(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = data!.buffer.asUint8List();

  int alphaAt(int x, int y) => pixels[(y * image.width + x) * 4 + 3];

  for (var y = image.height - 1; y >= 0; y--) {
    final inked = <int>[];
    for (var x = 0; x < image.width; x++) {
      // all but opaque: the drop shadow and the ground mark are baked into the file at well under
      // this, and they surround the point rather than ending on it
      if (alphaAt(x, y) > 200) inked.add(x);
    }
    if (inked.isEmpty) continue;
    return ((inked.first + inked.last + 1) / 2 / image.width, y);
  }
  fail('the drawing is empty');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final category in ShopCategory.values) {
    test(
      'the ${category.code} pin carries its point on its horizontal centre',
      () async {
        final bytes = await rootBundle.load(category.pinAsset);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();

        final (centre, row) = await _tipCentre(frame.image);

        // a pixel either way is the export's rounding, not a drawing that drifted
        expect(centre, closeTo(0.5, 0.01));
        expect(
          row,
          frame.image.height - 1,
          reason:
              'the point has to be the last row - room under it would stand the shop north of '
              'its address, since the bottom of the marker is what MapKit puts on the coordinate',
        );
      },
    );
  }

  testWidgets('a decoded pin paints at full size on its first build', (
    tester,
  ) async {
    for (final category in ShopCategory.values) {
      await tester.runAsync(() => ShopPinIcon.decoded(category));

      // one pump, deliberately: pumpAndSettle would hide an image that needed a second frame, and a
      // second frame is exactly what MapKit's off-screen rasterizer does not give it
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: ShopPinIcon(category: category)),
        ),
      );

      final size = tester.getSize(find.byType(ShopPinIcon));
      expect(size.height, ShopPinIcon.defaultHeight);
      expect(
        size.width,
        greaterThan(0),
        reason: '${category.code} rasterized blank',
      );
    }
  });
}
