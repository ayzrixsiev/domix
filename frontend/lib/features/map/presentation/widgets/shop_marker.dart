import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/stores/data/price_tier.dart';

// teardrop pin shape in brand orange with a shop icon inside, pointing down at its bottom tip.
// shared between ShopMarker (a tappable pin plotted on the map) and the location picker's fixed
// center pin, so both look consistent.
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
          child: Icon(
            CupertinoIcons.building_2_fill,
            color: Colors.white,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}

// a MapPinIcon that reacts to taps, used inside the map's MarkerLayer. optionally shows how this
// shop's basket compares to its market - "−4%" in green - or nothing at all for a shop with no
// published comparison.
//
// takes the tier and the percentage rather than a preformatted string, which is a change from when
// this showed an average check in сум: the colour is *derived* from the tier, so handing this
// widget a string would mean handing it a colour too, and two callers could then disagree about
// which number is green.
class ShopMarker extends StatelessWidget {
  const ShopMarker({super.key, required this.onTap, this.priceTier, this.priceDifferencePercent});

  final VoidCallback onTap;
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
  static const double labeledMarkerWidth = 90;

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
          const SizedBox(width: pinWidth, height: pinHeight, child: MapPinIcon()),
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
      // the white card is what makes this readable over map tiles, so the label inside it is bare
      // text - a tinted pill nested in a white card would be two rounded boxes deep for four
      // characters, and these tints are close to invisible over tiles anyway
      child: PriceTierPinLabel(tier: tier, differencePercent: differencePercent),
    );
  }
}

// draws the teardrop shape: a circle with a triangular tip at the bottom
class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primaryOrange;
    final circleRadius = size.width / 2;
    final circleCenter = Offset(size.width / 2, circleRadius);
    final tipInset = size.width * 0.18;

    final path = Path()
      ..moveTo(size.width / 2 - tipInset, circleRadius + tipInset * 0.7)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + tipInset, circleRadius + tipInset * 0.7)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(circleCenter, circleRadius, paint);

    canvas.drawCircle(
      circleCenter,
      circleRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
