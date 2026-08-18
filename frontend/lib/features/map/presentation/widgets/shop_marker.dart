import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

// teardrop pin shape in brand orange, pointing down at its bottom tip. shared between ShopMarker
// (a tappable pin plotted on the map) and the location picker's fixed center pin, so both look
// consistent.
//
// [category] decides what sits inside the circle, and the two answers are different *kinds* of
// thing rather than two glyphs:
//
//   * a plotted shop shows what it sells - store / bath / fence / scroll (see ShopCategory.icon)
//   * the location picker passes null and gets a **plain капля**: the teardrop with a white hole
//     punched through it, the mark every map app in the world uses for "this exact point"
//
// it used to draw `building_2` for the null case, and that was wrong in a way worth recording. the
// picker is not pointing at a building - it is pointing at wherever the user has dragged the map
// to, which may be a yard, a corner or a stretch of road. a building glyph makes a claim about the
// place, and it also makes the picker's pin look like a fifth shop category. a hole makes no claim
// at all, which is exactly the right amount for a point the user is still choosing.
//
// that is the whole reason [category] is nullable rather than defaulting to универсальный.
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
                // the hole. a filled white circle rather than a stroked ring: at 48px a ring would
                // be three concentric outlines deep once the pin's own white rim is counted, and
                // the solid dot is what reads as "punched through" instead of "drawn on".
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
                    // half the pin's width, where the filled cupertino glyph this replaced sat at
                    // 0.45. lucide is a stroke font: at the same nominal size it covers less area
                    // and reads lighter against the orange, so it has to be drawn bigger to carry
                    // the same weight.
                    size: size * 0.5,
                  ),
          ),
        ),
      ),
    );
  }
}

// a MapPinIcon that reacts to taps, used inside the map's MarkerLayer. two independent things about
// one shop, in two channels: the pin says what kind of shop it is, the label above it says how its
// basket compares to that market - a coloured dot plus "−4%" - or nothing at all for a shop with no
// published comparison, which since migration 000013 means any shop that has not priced its whole
// catalogue.
//
// it takes the tier and the percentage rather than a preformatted string, which is a change from
// when this showed an average check in сум: the colour is *derived* from the tier, so handing this
// widget a string would mean handing it a colour too, and two callers could then disagree about
// which number is green. the сум figure did not move to a smaller font - it moved off the map
// entirely, into the shop's own card, where there is room to label it.
class ShopMarker extends StatelessWidget {
  const ShopMarker({
    super.key,
    this.onTap,
    required this.category,
    this.priceTier,
    this.priceDifferencePercent,
  });

  /// Optional, and on the map it is **always** null.
  ///
  /// MapKit rasterizes this widget off-screen and draws the bitmap, so a `GestureDetector` inside it
  /// can never fire - taps arrive through the placemark's own listener instead (see `DomixMap`).
  /// The field stays because the widget is still a plain widget anywhere else it is mounted for
  /// real, and because a required callback that silently does nothing is worse than an absent one.
  final VoidCallback? onTap;
  final ShopCategory category;
  final PriceTier? priceTier;
  final int? priceDifferencePercent;

  // the pin itself is unchanged from before this label was added (44x50, matching the Marker size
  // map_screen.dart already used) - kept as an explicit SizedBox here so wrapping it in a Column
  // below can't accidentally shrink it back down to MapPinIcon's own smaller intrinsic size.
  static const double pinWidth = 44;
  static const double pinHeight = 50;
  static const double labelGap = 4;
  // approximate; only needs to be in the right ballpark since the Column below bottom-aligns its
  // children, so any slack from an imprecise estimate just adds empty space above the label
  static const double labelHeight = 26;
  // wide enough for the dot, the gap and "−20%" without the pill clipping. no longer a hard crop -
  // MapKit rasterizes this widget at whatever size it lays out to, where flutter_map cropped a
  // marker to the box it was given - but the number stays as the width the label was designed
  // against, and the pin's anchor assumes the raster is symmetric about its centre.
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
    // neutral hairline rather than the old orange outline: the pin below is already orange, so
    // outlining the label too made the pair read as one solid orange blob against the map. a soft
    // shadow does the separation work instead - a map is a busy backdrop, so the pill needs some
    // lift, just not a hard 15%-black edge.
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
      // white, not tinted with the tier's soft colour: a tinted pill inside a white card would be
      // two rounded boxes deep for four characters, and those tints are close to invisible over map
      // tiles anyway. the saturated dot inside carries the colour instead, which is the one form of
      // it that survives at this size.
      child: PriceTierPinLabel(tier: tier, differencePercent: differencePercent),
    );
  }
}

// draws the teardrop: one circle, one triangle, and a white outline around the pair.
//
// **the triangle's corners are the circle's tangent points, not two guessed offsets**, which is
// what makes this a teardrop rather than a ball with a spike under it. it used to put the base at a
// fixed fraction of the width, so the sides met the circle at an angle and the join pinched to
// almost nothing - at the size the location picker draws it (48px, and no glyph inside to look at)
// the tip read as a separate little triangle floating below the circle.
//
// the geometry is the standard tangent-from-an-external-point construction. with the tip at
// distance d below the centre of a circle of radius r, the two points where a line from the tip
// grazes the circle are:
//
//     x = cx ± r·√(1 − r²/d²)      y = cy + r²/d
//
// (in the right triangle centre-tangent-tip the angle at the centre has cos = r/d, because the
// radius meets a tangent at ninety degrees.) drawing the triangle to *those* points means its sides
// leave the circle along the circle's own direction, so the union has no corner in it.
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
