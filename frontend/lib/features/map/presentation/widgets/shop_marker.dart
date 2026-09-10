import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

// teardrop pin in brand orange, shared between ShopMarker and the location picker's centre pin.
//
// [category] decides what sits inside the circle, and the two answers are different *kinds* of
// thing: a plotted shop shows what it sells, while the picker passes null and gets a plain капля -
// the mark every map app uses for "this exact point". that is why it is nullable rather than
// defaulting to универсальный: the picker points at a yard or a stretch of road, and a building
// glyph would make a claim about the place and look like a fifth shop category.
class MapPinIcon extends StatelessWidget {
  const MapPinIcon({super.key, this.size = 40, this.category});

  final double size;
  final ShopCategory? category;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PinPainter(),
      child: SizedBox(
        width: size,
        height: size * 1.15,
        child: Padding(
          padding: EdgeInsets.only(bottom: size * 0.25),
          child: Center(
            child: category == null
                // a filled white circle rather than a stroked ring: at 48px a ring is three concentric outlines
                // deep once the pin's own rim is counted, and the solid dot reads as "punched through"
                ? Container(
                    width: size * 0.30,
                    height: size * 0.30,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  )
                : Icon(
                    category!.icon,
                    color: Colors.white,
                    // half the pin's width, where the filled cupertino glyph this replaced sat at 0.45: lucide is a
                    // stroke font and covers less area at the same nominal size
                    size: size * 0.5,
                  ),
          ),
        ),
      ),
    );
  }
}

// a MapPinIcon that reacts to taps. two channels about one shop: the pin says what kind of shop it
// is, the label says how its basket compares - or nothing, which since migration 000013 means any
// shop that has not priced its whole catalogue.
//
// it takes the tier and the percentage rather than a formatted string: the colour is derived from
// the tier, so two callers could otherwise disagree about which number is green.
class ShopMarker extends StatelessWidget {
  const ShopMarker({
    super.key,
    this.onTap,
    required this.category,
    this.priceTier,
    this.priceDifferencePercent,
  });

  /// Optional, and on the map it is **always** null: MapKit rasterizes this widget, so a
  /// `GestureDetector` inside it can never fire - taps arrive through the placemark's own listener.
  /// The field stays because the widget is still a plain widget anywhere else it is mounted for real.
  final VoidCallback? onTap;
  final ShopCategory category;
  final PriceTier? priceTier;
  final int? priceDifferencePercent;

  // an explicit SizedBox, so wrapping the pin in a Column below cannot shrink it back down to
  // MapPinIcon's own smaller intrinsic size
  static const double pinWidth = 44;
  static const double pinHeight = 50;
  static const double labelGap = 4;
  // approximate: the Column below bottom-aligns its children, so slack just adds space above
  static const double labelHeight = 26;
  // wide enough for the dot, the gap and "−20%" without the pill clipping. the pin's anchor assumes
  // the raster is symmetric about its centre.
  static const double labeledMarkerWidth = 96;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (priceTier case final tier?) ...[
            _PriceComparisonLabel(tier: tier, differencePercent: priceDifferencePercent),
            const SizedBox(height: labelGap),
          ],
          SizedBox(
            width: pinWidth,
            height: pinHeight,
            child: MapPinIcon(category: category),
          ),
        ],
      ),
    );
  }
}

class _PriceComparisonLabel extends StatelessWidget {
  const _PriceComparisonLabel({required this.tier, required this.differencePercent});

  final PriceTier tier;
  final int? differencePercent;

  @override
  Widget build(BuildContext context) {
    // a neutral hairline rather than the old orange outline: the pin below is already orange, so
    // outlining the label too made the pair read as one solid blob. a soft shadow separates instead.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(color: Color(0x1F101828), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      // white, not tinted with the tier's soft colour: a tinted pill inside a white card is two rounded
      // boxes deep for four characters, and those tints are near-invisible over map tiles anyway. the
      // saturated dot inside carries the colour instead.
      child: PriceTierPinLabel(tier: tier, differencePercent: differencePercent),
    );
  }
}

// draws the teardrop: one circle, one triangle, and a white outline around the pair.
//
// **the triangle's corners are the circle's tangent points, not two guessed offsets** - with the tip
// at distance d below the centre of a circle of radius r, the grazing points are
//
//     x = cx ± r·√(1 − r²/d²)      y = cy + r²/d
//
// so the sides leave the circle along its own direction and the union has no corner in it.
class _PinPainter extends CustomPainter {
  static const double _strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // half the stroke sits outside whatever it outlines, so the shape is inset by that much or the
    // rim is shaved off at the left, right and top edges of the box
    const inset = _strokeWidth / 2;
    final radius = size.width / 2 - inset;
    final center = Offset(size.width / 2, radius + inset);
    final tip = Offset(size.width / 2, size.height - inset);

    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

    final d = tip.dy - center.dy;
    Path shape = circle;
    // d > radius means the tip is genuinely outside the circle, which is the only case a tangent
    // exists for. a pin drawn shorter than it is wide would fail that, and gets a plain dot.
    if (d > radius) {
      final tangentX = radius * math.sqrt(1 - (radius * radius) / (d * d));
      final tangentY = center.dy + (radius * radius) / d;

      final triangle = Path()
        ..moveTo(center.dx - tangentX, tangentY)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(center.dx + tangentX, tangentY)
        ..close();

      // unioned into a single path, so the outline below traces the silhouette instead of drawing a
      // ring through the middle of the join
      shape = Path.combine(PathOperation.union, circle, triangle);
    }

    canvas.drawPath(shape, Paint()..color = AppColors.primaryOrange);
    canvas.drawPath(
      shape,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
