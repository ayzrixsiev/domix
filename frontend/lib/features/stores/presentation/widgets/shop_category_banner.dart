import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The cover a shop card opens with: **one picture per shop category**, drawn rather than fetched.
///
/// **Why it is painted and not a photograph.** Nothing writes `shops.image_url` - photo upload for
/// shops is deferred - so a hero band backed by that column would be an empty grey rectangle on every
/// shop in the market, which is the exact mistake the old map sheet's saturated orange banner was and
/// the reason the previous card had no cover at all. Shipping four stock photographs instead would
/// mean four files in the bundle that are a picture of *somebody else's* shop, and they would be the
/// only raster assets in the app.
///
/// A painted cover has none of those problems and one real advantage: it is the same picture for
/// every Сантехника shop, which is what makes it *information*. A customer who has opened three shop
/// cards learns the teal one is plumbing before reading a word - the same job the map pin's glyph
/// does, in the one place there is room to do it properly.
///
/// **The four palettes are the one place in this app with colour that is not the brand's**, and that
/// is deliberate rather than an oversight. Brand orange is reserved for primary actions and active
/// state (CLAUDE.md §9); a cover is neither, and four orange covers would say nothing about which
/// shop you are looking at. They are deep and desaturated - a material-yard palette, not a set of
/// highlighter pens - and each is dark enough to carry white text at well over 4.5:1.
///
/// If [Shop.imageUrl] ever starts arriving, the photograph goes here on top of the gradient with the
/// same overlay and the same rounded corners: this widget is the shape that layout is built around,
/// so that day costs one `Image.network` and no rethinking.
class ShopCategoryBanner extends StatelessWidget {
  const ShopCategoryBanner({
    super.key,
    required this.category,
    required this.name,
    required this.isVip,
    this.height = defaultHeight,
    this.contentInset = 16,
  });

  final ShopCategory category;

  /// The shop's own name, laid over the picture. It is the only text on the cover, and it is here
  /// rather than in the section below because that section answers "what kind of shop is this and
  /// where" - a picture with the name on it is what tells you *whose* card you opened, in both the
  /// pushed route (which has no title bar of its own) and the map's sheet (which has no bar at all).
  final String name;

  /// Draws the placement mark. **Not a pill** - VIP is set in white small-caps beside a star, on a
  /// cover dark enough not to need a chip behind it. A white capsule up there would be a second
  /// bright object competing with the name for the same band.
  final bool isVip;

  /// 200 in both the pushed card and the map's sheet, so the two are the same screen at different
  /// sizes rather than two layouts. Tall enough to read as a cover, short enough that the price
  /// comparison - the reason this app exists - is still on the first screenful under it.
  static const double defaultHeight = 200;

  final double height;

  /// How far above the cover's bottom edge the name sits.
  ///
  /// **A caller-supplied number because something is usually parked on that edge.** The shop card
  /// laps its identity block a couple of dozen pixels onto the picture, and a name at the default
  /// inset would spend its second line behind that card - visible in a mock-up, invisible on any
  /// shop whose name wraps. The scrim moves with it, so the two cannot drift apart.
  final double contentInset;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(category);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.light, palette.dark],
                ),
              ),
            ),

            // the motif. `isComplex`/`willChange: false` tells the engine this is worth rasterizing
            // into a cached layer once - it is thirty-odd glyphs and it never changes, and without
            // the hint it would be re-painted on every frame the card scrolls.
            Positioned.fill(
              child: CustomPaint(
                painter: _MotifPainter(icon: category.icon),
                isComplex: true,
                willChange: false,
              ),
            ),

            // a scrim under the name only. the gradient's own bottom-right corner is its darkest
            // point, but the name sits bottom-*left*, which on some palettes is the lightest place
            // on the cover - so the text gets its own floor rather than trusting the background.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: contentInset + 84,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x59000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),

            if (isVip)
              const Positioned(top: 14, right: 16, child: _VipMark()),

            Positioned(
              left: 18,
              right: 18,
              bottom: contentInset,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  height: 1.18,
                  letterSpacing: -0.4,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The placement mark: a star and three letters, no container.
///
/// «VIP» is not translated anywhere in this app - it is the name of the tier, the same three letters
/// in ru and uz - so this needs no strings and takes none.
class _VipMark extends StatelessWidget {
  const _VipMark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, color: AppColors.starYellow, size: 17),
        SizedBox(width: 5),
        Text(
          'VIP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Color(0x40000000), blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

/// The two gradient stops of one category's cover.
class _Palette {
  const _Palette(this.light, this.dark);

  final Color light;
  final Color dark;
}

/// **An exhaustive switch, for the same reason [ShopCategory.label] and [ShopCategory.icon] are
/// ones:** a fifth shop category becomes a compile error here rather than a cover that silently
/// falls back to somebody else's colour.
///
/// Chosen as a set rather than one at a time - what matters is that no two are confusable at a
/// glance, which is the whole point of the cover carrying information at all. Graphite for the shop
/// that sells a bit of everything, teal for water, forest for timber, plum for the decorative trade.
_Palette _paletteFor(ShopCategory category) => switch (category) {
      ShopCategory.universal => const _Palette(Color(0xFF4B566B), Color(0xFF232B39)),
      ShopCategory.plumbing => const _Palette(Color(0xFF1E717B), Color(0xFF0E3D45)),
      ShopCategory.wood => const _Palette(Color(0xFF4E7048), Color(0xFF283E27)),
      ShopCategory.wallpaper => const _Palette(Color(0xFF6E4C77), Color(0xFF3D2A45)),
    };

/// The texture over the gradient: the category's own glyph, tiled small across a tilted grid, with
/// one large copy anchored at the bottom right.
///
/// **The glyphs are drawn through a [TextPainter], because a Lucide icon *is* a character in a
/// font.** An `Icon` widget could not be tiled thirty times without thirty widgets in the tree; this
/// lays the codepoint out once per size and stamps it, which is one text layout and a loop.
class _MotifPainter extends CustomPainter {
  const _MotifPainter({required this.icon});

  final IconData icon;

  /// how far apart the small glyphs sit, centre to centre
  static const double _step = 58;

  /// how far the grid is rotated, in radians. a few degrees is what stops it reading as graph paper
  /// - a pattern that lines up with the card's own edges looks like a mistake in the layout rather
  /// than like a texture.
  static const double _tilt = -0.22;

  @override
  void paint(Canvas canvas, Size size) {
    // a soft light from the top-left corner, which is what stops the gradient reading as a flat
    // two-colour ramp. drawn before the glyphs so they sit in the light rather than under it.
    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.8, -1.0),
        radius: 1.25,
        colors: const [Color(0x26FFFFFF), Color(0x00FFFFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);

    final small = _glyph(20, const Color(0x1AFFFFFF));
    canvas.save();
    // rotate about the centre, then cover a box big enough that the corners are still filled once
    // the grid is turned - `diagonal` is the safe over-draw for any rotation.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_tilt);
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    for (var y = -diagonal / 2; y < diagonal / 2; y += _step) {
      // every other row is offset half a step, so the glyphs read as a weave rather than as columns
      final rowOffset = ((y / _step).round().isEven ? 0.0 : _step / 2) - diagonal / 2;
      for (var x = rowOffset; x < diagonal / 2; x += _step) {
        small.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();

    // the anchor: one large glyph half off the bottom-right corner, which is what makes the cover
    // read as a picture of something rather than as patterned paper
    final large = _glyph(150, const Color(0x1FFFFFFF));
    large.paint(
      canvas,
      Offset(size.width - large.width * 0.68, size.height - large.height * 0.62),
    );
  }

  TextPainter _glyph(double fontSize, Color colour) {
    return TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  // the icon is the only thing this painter reads, and it comes from the shop's category, which
  // cannot change while the card is open
  @override
  bool shouldRepaint(_MotifPainter oldDelegate) => oldDelegate.icon != icon;
}
