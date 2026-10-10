import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The cover a shop card opens with: **one painted picture per shop category**, full width and up to
/// the very top of the screen.
///
/// Painted rather than photographed because nothing writes a cover image yet, and four stock
/// photographs would be pictures of *somebody else's* shop.
///
/// **Each category gets its own palette and its own material**, because the cover is the largest
/// thing on the card and four identical oranges would say nothing: bricks on brand orange, pipes on
/// steel blue, boards on timber brown, rolls on sage. Brand orange stays the *universal* shop's,
/// which is what keeps the palette from reading as four unrelated apps - and the mark sitting on the
/// seam below ([ShopCategoryAvatar]) is brand orange on all four, so every cover still carries it.
///
/// **The top of every cover stays near-white on purpose** - the status bar sits over it on the
/// pushed route, and the overlay style there is `dark`.
///
/// Four layers: the ground, a faint draughting grid, one wide tilted band running off both edges,
/// and the category's material stacked along that band.
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

  /// how far the band and its parallels are tilted, anticlockwise
  static const double _tiltDegrees = -10;

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
        painter: _CoverPainter(art: _artFor(category)),
        isComplex: true,
        willChange: false,
      ),
    );
  }
}

/// What a cover is made of. The materials are drawn, not listed, so a fifth one is a case here and a
/// case in [_CoverPainter._paintMaterial] - the analyzer names both.
enum _Material { bricks, pipes, boards, rolls }

/// One category's cover. [pale] and [deep] are the ground, which runs white → pale → deep from the
/// top; [bandFrom] and [bandTo] are the band the material is stacked on.
typedef _CoverArt = ({Color pale, Color deep, Color bandFrom, Color bandTo, _Material material});

_CoverArt _artFor(ShopCategory category) => switch (category) {
      ShopCategory.universal => (
          pale: const Color(0xFFFFF0E2),
          deep: const Color(0xFFFFD6B0),
          bandFrom: const Color(0xFFFF8A2B),
          bandTo: const Color(0xFFE85D04),
          material: _Material.bricks,
        ),
      ShopCategory.plumbing => (
          pale: const Color(0xFFEBF3F9),
          deep: const Color(0xFFC3D9EB),
          bandFrom: const Color(0xFF6D9EC6),
          bandTo: const Color(0xFF2F5D86),
          material: _Material.pipes,
        ),
      ShopCategory.wood => (
          pale: const Color(0xFFF8F0E5),
          deep: const Color(0xFFE6CDAC),
          bandFrom: const Color(0xFFC98B4B),
          bandTo: const Color(0xFF8A5524),
          material: _Material.boards,
        ),
      ShopCategory.wallpaper => (
          pale: const Color(0xFFF0F4EB),
          deep: const Color(0xFFD1E0C2),
          bandFrom: const Color(0xFF8FA87A),
          bandTo: const Color(0xFF55723F),
          material: _Material.rolls,
        ),
    };

class _CoverPainter extends CustomPainter {
  const _CoverPainter({required this.art});

  final _CoverArt art;

  /// where the band starts, as a share of the cover's height.
  ///
  /// **The two ends of a tilted band are what this number is up against.** The tilt lifts the right
  /// end about 34px and drops the left end the same, the bottom 26 of the cover is under the white
  /// surface, and the top ~50 is the status bar - so the band has to start low enough that its high
  /// end clears the status bar and high enough that its low end is not swallowed by the surface.
  /// Together with the 10° tilt that leaves about half the height, and there is little slack in it:
  /// a steeper tilt runs the band's high corner into the status bar, and a lower start buries the
  /// low one under the surface.
  static const double _bandAt = 0.50;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // **A CustomPaint does not clip, and every layer below overdraws deliberately.** Without this the
    // band - three screen widths wide and twice the cover tall - paints over the details and the
    // catalogue underneath, which looks like a rendering fault rather than a layout one.
    canvas.clipRect(rect);

    // 1. the ground. white at the top, where the status bar sits, into the category's own tint.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.2, 1),
          colors: [AppColors.surfaceWhite, art.pale, art.deep],
          stops: const [0, 0.38, 1],
        ).createShader(rect),
    );

    // 2. the draughting grid, in the category's own hue
    final grid = Paint()
      ..color = art.bandTo.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = ShopCategoryBanner._gridStep; x < size.width; x += ShopCategoryBanner._gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = ShopCategoryBanner._gridStep; y < size.height; y += ShopCategoryBanner._gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // 3. the band and what is stacked on it, in one rotated frame so they cannot drift out of
    // alignment. deliberately over-drawn on every side: the rotation swings the corners outward, and a
    // band cut to the box would leave a pale wedge in the bottom-left at some screen widths.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(ShopCategoryBanner._tiltDegrees * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);

    final bandTop = size.height * _bandAt;
    final bandRect = Rect.fromLTWH(-size.width, bandTop, size.width * 3, size.height * 2);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [art.bandFrom, art.bandTo],
        ).createShader(bandRect),
    );

    // the two thin parallels above it - what makes the band read as one of a set of lines rather than
    // a block of colour that happens to be diagonal
    for (final (offset, alpha) in const [(10.0, 0.30), (22.0, 0.15)]) {
      canvas.drawRect(
        Rect.fromLTWH(-size.width, bandTop - offset, size.width * 3, 3),
        Paint()..color = art.bandFrom.withValues(alpha: alpha),
      );
    }

    _paintMaterial(canvas, size, bandTop);
    canvas.restore();
  }

  /// The category's goods, stacked along the band in white. **Fill and outline both, always**: a
  /// translucent white fill alone sinks into the band's lighter end, and the outline is what holds
  /// the silhouette there.
  ///
  /// **The stack gets ~46px under [_bandAt] and no more.** The tilt puts one end of it about 34px
  /// higher than the other, so anything taller is cut off by the white surface at the low end and
  /// shows only at the high one - a cover with its material in one corner.
  void _paintMaterial(Canvas canvas, Size size, double bandTop) {
    final fill = Paint()..color = const Color(0x33FFFFFF);
    final line = Paint()
      ..color = const Color(0x80FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // the stack runs off both edges, so no screen width shows where it starts
    final left = -size.width * 0.3;
    final right = size.width * 1.3;
    final span = right - left;

    void shape(Rect r, [double radius = 3]) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas
        ..drawRRect(rr, fill)
        ..drawRRect(rr, line);
    }

    switch (art.material) {
      case _Material.bricks:
        // every other course shifted half a brick, which is the bond that says "wall" rather than "grid"
        for (var row = 0; row < 2; row++) {
          final y = bandTop + 2 + row * 24;
          for (var x = left + (row.isOdd ? 27 : 0); x < right; x += 54) {
            shape(Rect.fromLTWH(x, y, 46, 19));
          }
        }
      case _Material.pipes:
        for (var i = 0; i < 2; i++) {
          final y = bandTop + 3 + i * 25;
          shape(Rect.fromLTWH(left, y, span, 18), 9);
          // the bore, which is the whole difference between a pipe and a bar with round ends
          canvas.drawLine(Offset(left, y + 5), Offset(right, y + 5), line);
          // and the couplings along it, proud of the pipe top and bottom
          for (var x = left + 50 + i * 80; x < right; x += 160) {
            shape(Rect.fromLTWH(x, y - 4, 15, 26), 2);
          }
        }
      case _Material.boards:
        // **both ends of most boards are inside the picture.** a board running off both edges is a
        // stripe, and three stripes are the band's own parallels drawn again - it is the cut ends,
        // staggered, that make the stack read as sawn timber.
        const runs = [(0.0, 0.58), (0.66, 1.0), (0.12, 0.74), (0.82, 1.0)];
        for (var i = 0; i < runs.length; i++) {
          final (from, to) = runs[i];
          final y = bandTop + 3 + (i < 2 ? 0 : 1) * 24;
          shape(Rect.fromLTWH(left + span * from, y, span * (to - from), 20), 2);
        }
      case _Material.rolls:
        for (var x = left + 20; x < right; x += 104) {
          // the hung sheet
          shape(Rect.fromLTWH(x, bandTop + 2, 52, 42), 4);
          // the drop lines are what make it paper rather than a tile
          for (var s = 1; s < 3; s++) {
            canvas.drawLine(
              Offset(x + s * 17.3, bandTop + 8),
              Offset(x + s * 17.3, bandTop + 38),
              line,
            );
          }
          // the roll beside it, seen end on
          final end = Offset(x + 74, bandTop + 23);
          canvas
            ..drawCircle(end, 15, fill)
            ..drawCircle(end, 15, line)
            ..drawCircle(end, 5, line);
        }
    }
  }

  // the art is the only thing this painter reads, and a shop's category cannot change while the
  // card is open
  @override
  bool shouldRepaint(_CoverPainter oldDelegate) => oldDelegate.art != art;
}
