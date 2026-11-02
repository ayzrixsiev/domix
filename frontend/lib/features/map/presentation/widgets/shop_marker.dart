import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

// the location picker's centre pin: a plain teardrop in brand orange.
//
// it points at a yard or a stretch of road, so it carries no trade - a shop's drawing here would
// both claim something about the place and read as a fifth shop category. A shop is [ShopPinIcon].
class MapPinIcon extends StatelessWidget {
  const MapPinIcon({super.key, this.size = 40});

  final double size;

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
            // a filled white circle rather than a stroked ring: at 48px a ring is three concentric outlines
            // deep once the pin's own rim is counted, and the solid dot reads as "punched through"
            child: Container(
              width: size * 0.30,
              height: size * 0.30,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A shop on the map, drawn as its trade: the toolbox, the pipe, the rolls, the timber
/// ([ShopCategory.pinAsset]).
///
/// Sized by height alone, so all four read as one set however wide each drawing happens to be. That
/// height is what the bitmap is *rasterized* at and also the largest it is ever drawn: between
/// [detailZoom] and [fullScaleZoom] MapKit scales the bitmap down - see [scaleForZoom].
///
/// **The drawing's point is the file's bottom row, and nothing is painted below it**: that row is
/// the shop's coordinate, so transparent room under the point would stand every shop that far north
/// of its address. The drop shadow and the mark on the ground - which are what make a pin land on
/// the map rather than sit on top of it like a sticker - are both baked into the file above that
/// row, and the file carries its own clearance at the top and sides for the shadow's blur.
///
/// **Mount it only behind [decoded].** MapKit rasterizes a pin on a one-shot offscreen tree that
/// never gets a second frame, so an asset still decoding paints nothing at all - and the
/// placemark's `cacheable: true` would then keep that blank for the rest of the session.
class ShopPinIcon extends StatelessWidget {
  const ShopPinIcon({
    super.key,
    required this.category,
    this.height = defaultHeight,
  });

  final ShopCategory category;
  final double height;

  static const double defaultHeight = 34;

  /// The zoom a shop is first drawn as a pin rather than a [ShopDot], and the zoom the pin reaches
  /// full size at. **The size curve and the map's own thresholds are one design**, so they are one
  /// pair of constants and MapScreen reads them rather than keeping its own.
  static const double detailZoom = 13;
  static const double fullScaleZoom = 15;

  /// What the pin shrinks to at [detailZoom]. Not less: below this the toolbox and the timber stop
  /// telling each other apart, and four indistinguishable marks are what [ShopDot] is already for.
  static const double _minScale = 0.7;

  /// How much MapKit should scale this pin's bitmap at [zoom]. It scales the raster rather than
  /// rebuilding anything, which is what lets the pins grow smoothly under a pinch instead of
  /// popping between two sizes - and tying their size to the zoom is what puts them *on* the map
  /// rather than over it.
  ///
  /// **Full size from [fullScaleZoom] up and never larger**: past the raster it is a blurred
  /// bitmap. The price label above the pin is what sets the bottom of the range - it is 13px type,
  /// and MapKit scales the whole marker - so the label is withheld below that zoom too.
  static double scaleForZoom(double zoom) {
    final progress = ((zoom - detailZoom) / (fullScaleZoom - detailZoom)).clamp(
      0.0,
      1.0,
    );
    return _minScale + (1 - _minScale) * progress;
  }

  /// Completes once this category's drawing is in the image cache, so the [Image] below paints on
  /// its first build. Resolved against [ImageConfiguration.empty] rather than a `BuildContext`: a
  /// pin has none, and with no density variants of these files every configuration asks for the
  /// same file at scale 1 anyway. A failed decode completes too - a missing pin beats no map.
  static Future<void> decoded(ShopCategory category) {
    final completer = Completer<void>();
    final stream = AssetImage(
      category.pinAsset,
    ).resolve(ImageConfiguration.empty);

    late final ImageStreamListener listener;
    void finish() {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    }

    listener = ImageStreamListener(
      (_, _) => finish(),
      onError: (_, _) => finish(),
    );
    stream.addListener(listener);

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      category.pinAsset,
      height: height,
      // the file is ~6x the height it is drawn at, and the default `low` leaves the diagonals of a
      // glyph ragged at that reduction
      filterQuality: FilterQuality.medium,
    );
  }
}

// two channels about one shop: the pin says what kind of shop it is, the label how its basket
// compares - or nothing, which means it has not priced its whole catalogue.
//
// it takes the tier and the percentage rather than a formatted string: the colour is derived from the
// tier, so two callers could otherwise disagree about which number is green.
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

  @override
  Widget build(BuildContext context) {
    // the column centres its children, and that is what puts the label over the *point*: every pin
    // file carries its own tip on its horizontal centre, so the column's centre is the tip whatever
    // the drawing's width, and the placemark anchors at (0.5, 1.0) for all four categories.
    //
    // no gap under the label: the pin file carries its own clearance for the drop shadow's blur,
    // and a SizedBox on top of it stranded the label about twice as far up as it reads best.
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (priceTier case final tier?)
            _PriceComparisonLabel(
              tier: tier,
              differencePercent: priceDifferencePercent,
            ),
          ShopPinIcon(category: category),
        ],
      ),
    );
  }
}

/// What a shop is drawn as while the map is zoomed out: a plain dot.
///
/// at city zoom the glyph is unreadable and seventy price labels overlap into a wall of white pills,
/// but **an empty map is a worse answer than a scatter of dots** - the scatter is what the user came
/// to see. the glyph and the price arrive on zoom-in.
///
/// every dot draws identically, so the whole city costs MapKit **one** raster, which is why
/// [visualKey] is a constant here rather than built per shop.
class ShopDot extends StatelessWidget {
  const ShopDot({super.key});

  /// The raster cache key for every dot there will ever be.
  static const String visualKey = 'shop-dot';

  /// The box the dot is centred in, so the pin anchors at its middle (0.5, 0.5) rather than at a
  /// teardrop's tip.
  static const double size = 16;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryOrange,
        shape: BoxShape.circle,
        // the same white rim the teardrop carries: over dark map tiles an unrimmed orange dot
        // disappears into a park or a motorway
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x33101828), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// «Вы здесь» - the one mark on the map that is not a shop, so it is the one mark that is not
/// orange. Blue because every map app's own-location dot is blue: the convention is what stops it
/// being read as a seventy-first shop.
class UserLocationDot extends StatelessWidget {
  const UserLocationDot({super.key});

  static const String visualKey = 'user-location';

  /// includes the halo; the solid dot inside is [_coreSize]
  static const double size = 28;
  static const double _coreSize = 16;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: _coreSize,
          height: _coreSize,
          decoration: BoxDecoration(
            color: AppColors.accentBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            // the halo, drawn as a shadow rather than a second box: one widget, and it fades out
            // the way an accuracy ring does
            boxShadow: [
              BoxShadow(
                color: AppColors.accentBlue.withValues(alpha: 0.22),
                blurRadius: 0,
                spreadRadius: 5,
              ),
              const BoxShadow(color: Color(0x33101828), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
        ),
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
