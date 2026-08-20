import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The cover a shop card opens with: **one painted picture per shop category**, in white and brand
/// orange, running the full width of the screen and up to the very top of it.
///
/// **Why it is painted and not a photograph.** Nothing writes `shops.image_url` - photo upload for
/// shops is deferred - so a hero band backed by that column would be an empty grey rectangle on
/// every shop in the market. Shipping four stock photographs instead would mean four files in the
/// bundle that are a picture of *somebody else's* shop, and they would be the only raster assets in
/// the app. A painted cover has neither problem, costs nothing to download, and is sharp at any
/// density.
///
/// ## The composition, and why it is one picture rather than a texture
///
/// It was a deep two-stop gradient per category with the category's glyph tiled thirty times across
/// a tilted grid. Two things were wrong with it. The tiling read as patterned wrapping paper rather
/// than as a cover - a *lot* of small marks is decoration, and decoration is what a reader skips.
/// And the four palettes (graphite, teal, forest, plum) were the one place in the app with colour
/// that was not the brand's, so the top of the most important screen in the product was the one
/// surface that did not look like Domix.
///
/// What replaced it is a single composition, built out of four elements and nothing else:
///
///  1. A near-white ground, warming to [AppColors.primarySoft] toward the bottom-right. **The top
///     stays white on purpose** - on the pushed route this band runs underneath the status bar, and
///     the clock and battery up there are painted dark (`SystemUiOverlayStyle.dark`).
///  2. A faint orange draughting grid, [_gridStep] apart. It is a texture rather than a picture:
///     what it does is stop the white half reading as an area that failed to load.
///  3. **The ribbon** - one wide orange band across the lower half at [_tiltDegrees], running off
///     both edges, with two thin parallels above it. This is the element carrying the brand, and it
///     runs off the edges because a band that stopped short would read as a rectangle drawn on the
///     cover rather than as the cover itself.
///  4. **The mark** - a white disc with the category's own glyph inside it, sitting on the ribbon.
///     It is the map pin's head with its colours swapped, which is the one piece of information
///     this cover carries: someone who arrived by tapping an orange teardrop with a bath in it
///     opens a card wearing the same bath.
///
/// **What the white-and-orange palette costs.** The old covers told you the category *by colour* -
/// teal was plumbing before you read a word. With one palette for all four, the glyph in the disc
/// is the only channel left, exactly as it is on the pin. That is a real loss and it was the
/// founder's call: a cover that does not look like the rest of the app is the worse trade.
///
/// If [Shop.imageUrl] ever starts arriving, the photograph goes in as a fifth layer under the
/// ribbon with the same height and the same corners: this widget is the shape the card's layout is
/// built around, so that day costs one `Image.network` and no rethinking.
class ShopCategoryBanner extends StatelessWidget {
  const ShopCategoryBanner({
    super.key,
    required this.category,
    this.height = defaultHeight,
  });

  final ShopCategory category;

  /// 240 of visible picture, up from the 200 it was.
  ///
  /// The cover is now full-bleed - no page gutter either side, no rounded corners of its own - so
  /// it had room to grow without pushing the price comparison off the first screenful. On the map's
  /// sheet the sheet's own [AppRadius.lg] corners crop the top two, which is the shape this was
  /// drawn for; on the pushed route the extra height is where the status bar sits.
  static const double defaultHeight = 240;

  final double height;

  /// how far the ribbon and its parallels are tilted, anticlockwise
  static const double _tiltDegrees = -15;

  /// centre-to-centre spacing of the draughting grid
  static const double _gridStep = 30;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        // one composition that never changes for the life of the card, so it is worth rasterizing
        // into a cached layer instead of repainting on every scroll frame
        painter: _CoverPainter(icon: category.icon),
        isComplex: true,
        willChange: false,
      ),
    );
  }
}

/// Everything on the cover, in one painter.
///
/// **The glyph is drawn through a [TextPainter], because a Lucide icon *is* a character in a
/// font.** That was true of the tiled version and is still the cheapest way to get one: it lays the
/// codepoint out once and stamps it, with no widget in the tree.
class _CoverPainter extends CustomPainter {
  const _CoverPainter({required this.icon});

  final IconData icon;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // **A CustomPaint does not clip, and every layer below overdraws deliberately.** Without this
    // the ribbon - three screen widths wide and twice the cover tall - paints straight over the
    // details and the catalogue underneath it, which is one solid orange screen: it looks like a
    // rendering fault rather than a layout one, so it is worth an explicit line.
    canvas.clipRect(rect);

    // 1. the ground. warm at the bottom-right, white at the top - the status bar sits on the white.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment(0.2, 1),
          colors: [AppColors.surfaceWhite, AppColors.primarySoft],
        ).createShader(rect),
    );

    // 2. the draughting grid
    final grid = Paint()
      ..color = AppColors.primaryOrange.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = ShopCategoryBanner._gridStep; x < size.width; x += ShopCategoryBanner._gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = ShopCategoryBanner._gridStep; y < size.height; y += ShopCategoryBanner._gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // 3. the ribbon, drawn in a rotated frame so the band and its two parallels cannot drift out of
    // alignment with each other.
    //
    // it is deliberately over-drawn on every side - a full screen width past each edge and twice
    // the cover's height downward - because the rotation swings the corners outward and a band cut
    // to the box would leave a pale wedge in the bottom-left corner at some screen widths and not
    // at others.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(ShopCategoryBanner._tiltDegrees * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);

    final bandTop = size.height * 0.52;
    final bandRect = Rect.fromLTWH(-size.width, bandTop, size.width * 3, size.height * 2);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A2B), Color(0xFFF25C00)],
        ).createShader(bandRect),
    );

    // the two thin parallels above it. they are what makes the band read as one of a set of lines
    // rather than as a block of colour that happens to be diagonal.
    for (final (offset, alpha) in const [(13.0, 0.28), (28.0, 0.14)]) {
      canvas.drawRect(
        Rect.fromLTWH(-size.width, bandTop - offset, size.width * 3, 3),
        Paint()..color = AppColors.primaryOrange.withValues(alpha: alpha),
      );
    }
    canvas.restore();

    // 4. the mark: the map pin's head, inverted. a white disc with a soft shadow so it sits *on*
    // the ribbon rather than looking punched out of it.
    final centre = Offset(size.width * 0.74, size.height * 0.55);
    const radius = 46.0;
    canvas.drawCircle(
      centre.translate(0, 4),
      radius,
      Paint()
        ..color = const Color(0x387A3600)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(centre, radius, Paint()..color = AppColors.surfaceWhite);

    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 44,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: AppColors.primaryOrange,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));
  }

  // the icon is the only thing this painter reads, and it comes from the shop's category, which
  // cannot change while the card is open
  @override
  bool shouldRepaint(_CoverPainter oldDelegate) => oldDelegate.icon != icon;
}
