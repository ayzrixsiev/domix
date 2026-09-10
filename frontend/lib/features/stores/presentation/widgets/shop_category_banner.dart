import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The cover a shop card opens with: **one painted picture per shop category**, in white and brand
/// orange, full width and up to the very top of the screen.
///
/// Painted rather than photographed because nothing writes `shops.image_url` yet, and four stock
/// photographs would be pictures of *somebody else's* shop.
///
/// Four elements: a near-white ground warming to [AppColors.primarySoft] (**the top stays white on
/// purpose** - the status bar sits over it), a faint orange grid so the white half does not read as
/// a failed load, one wide orange ribbon running off both edges, and a white disc carrying the
/// category's glyph. One palette for all four means that glyph is the only channel telling them
/// apart, as on the pin.
class ShopCategoryBanner extends StatelessWidget {
  const ShopCategoryBanner({
    super.key,
    required this.category,
    this.height = defaultHeight,
  });

  final ShopCategory category;

  /// 240 of visible picture. The cover is full-bleed, so it had room to grow without pushing the price
  /// comparison off the first screenful. On the map's sheet the sheet's own [AppRadius.lg] corners
  /// crop the top two; on the pushed route the extra height is where the status bar sits.
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
        // one composition that never changes for the life of the card, so it is worth rasterizing into a
        // cached layer instead of repainting on every scroll frame
        painter: _CoverPainter(icon: category.icon),
        isComplex: true,
        willChange: false,
      ),
    );
  }
}

/// Everything on the cover, in one painter. **The glyph is drawn through a [TextPainter], because a
/// Lucide icon *is* a character in a font** - the cheapest way to get one, with no widget in the tree.
class _CoverPainter extends CustomPainter {
  const _CoverPainter({required this.icon});

  final IconData icon;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // **A CustomPaint does not clip, and every layer below overdraws deliberately.** Without this the
    // ribbon - three screen widths wide and twice the cover tall - paints over the details and the
    // catalogue underneath, which looks like a rendering fault rather than a layout one.
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
    // alignment. deliberately over-drawn on every side: the rotation swings the corners outward, and a
    // band cut to the box would leave a pale wedge in the bottom-left at some screen widths.
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

    // the two thin parallels above it - what makes the band read as one of a set of lines rather than
    // a block of colour that happens to be diagonal
    for (final (offset, alpha) in const [(13.0, 0.28), (28.0, 0.14)]) {
      canvas.drawRect(
        Rect.fromLTWH(-size.width, bandTop - offset, size.width * 3, 3),
        Paint()..color = AppColors.primaryOrange.withValues(alpha: alpha),
      );
    }
    canvas.restore();

    // 4. the mark: the map pin's head, inverted. a white disc with a soft shadow so it sits *on* the
    // ribbon rather than looking punched out of it.
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

  // the icon is the only thing this painter reads, and a shop's category cannot change while the
  // card is open
  @override
  bool shouldRepaint(_CoverPainter oldDelegate) => oldDelegate.icon != icon;
}
