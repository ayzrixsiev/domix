import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';

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

// a MapPinIcon that reacts to taps, used inside the map's MarkerLayer. optionally shows a small
// preformatted label (e.g. "150 000 сум") above the pin - map_screen.dart builds the exact text
// (locale + number formatting is its job, not this widget's) and passes null to omit it entirely.
class ShopMarker extends StatelessWidget {
  const ShopMarker({super.key, required this.onTap, this.averagePaycheckLabel});

  final VoidCallback onTap;
  final String? averagePaycheckLabel;

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
          if (averagePaycheckLabel != null) ...[
            _PaycheckLabel(text: averagePaycheckLabel!),
            const SizedBox(height: labelGap),
          ],
          const SizedBox(width: pinWidth, height: pinHeight, child: MapPinIcon()),
        ],
      ),
    );
  }
}

class _PaycheckLabel extends StatelessWidget {
  const _PaycheckLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryOrange, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textDark),
      ),
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
