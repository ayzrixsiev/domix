import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/products/data/product_category.dart';

// One icon family, monochrome: Lucide ships a real glyph font, and both the label and the glyph come
// off `ProductCategory`, so a category cannot look different depending on the screen.
//
// **A pager, not a taller grid** - twelve in one static grid meant three rows dominating the feed,
// and it is also what retired the "Все →" action.
//
// **No white surface anywhere in this section**, behind it or behind a tile, and **no shop count on
// the tiles** - that cost a database aggregate on every home load.
class PopularCategoriesGrid extends StatefulWidget {
  const PopularCategoriesGrid({super.key, required this.onCategoryTap});

  /// passed in rather than pushed from here, so this stays a pure renderer with no route knowledge
  final void Function(ProductCategory category) onCategoryTap;

  @override
  State<PopularCategoriesGrid> createState() => _PopularCategoriesGridState();
}

class _PopularCategoriesGridState extends State<PopularCategoriesGrid> {
  static const int _columns = 4;
  static const int _rows = 2;
  static const int _perPage = _columns * _rows;

  // the content's real height (64 box + 7 gap + two 13.2px lines) plus slack, times two rows. a
  // constant rather than a childAspectRatio - see the delegate below.
  static const double _cellHeight = 100;
  static const double _rowGap = 6;
  static const double _pageHeight = _cellHeight * _rows + _rowGap * (_rows - 1);

  late final PageController _controller;

  /// derived, so a thirteenth category grows the pager instead of being silently hidden
  int get _pageCount => (ProductCategory.values.length / _perPage).ceil();

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _pageHeight,
          child: PageView.builder(
            controller: _controller,
            physics: const BouncingScrollPhysics(),
            itemCount: _pageCount,
            itemBuilder: (context, page) {
              // clamped at the end: the last page is partial - twelve categories over eight-per-page leaves four
              final start = page * _perPage;
              final end = math.min(start + _perPage, ProductCategory.values.length);
              final categories = ProductCategory.values.sublist(start, end);

              return GridView.builder(
                // the PageView is the scrollable here; a grid that also scrolled would fight it for the same drag
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  // a fixed row height rather than childAspectRatio, which derives height from *width* - so the cell
                  // grew on a wide phone and shrank on a narrow one, until a two-line label no longer fit. this is
                  // the content's real height plus slack, and it holds on every screen width.
                  mainAxisExtent: _cellHeight,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: _rowGap,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return _CategoryTile(
                    icon: category.icon,
                    label: category.label(strings),
                    onTap: () => widget.onCategoryTap(category),
                  );
                },
              );
            },
          ),
        ),
        // 4, not the 14 this started at: the dots carry their own vertical touch padding, so the gap the
        // eye measures is that padding plus whatever is added here
        const SizedBox(height: 4),
        _PageDots(controller: _controller, pageCount: _pageCount),
      ],
    );
  }
}

/// The dots under the pager, driven by the controller's *fractional* page: `onPageChanged` fires
/// after the page has snapped, so a dot driven by it jumps a beat behind the finger.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.controller, required this.pageCount});

  final PageController controller;
  final int pageCount;

  static const double _dotSize = 6;
  static const double _activeWidth = 20;

  @override
  Widget build(BuildContext context) {
    if (pageCount < 2) return const SizedBox.shrink();

    return AnimatedBuilder(
      // the controller ticks on every scroll frame, so only the dots rebuild - not the tiles above
      animation: controller,
      builder: (context, _) {
        // `page` is null until the PageView has been laid out and `hasClients` is false before it is
        // attached - both on the first frame, so fall back rather than render with no active dot
        final current = controller.hasClients && controller.page != null
            ? controller.page!
            : controller.initialPage.toDouble();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pageCount; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _Dot(
                // 1 when this page is centred, 0 a full page away, fractional mid-drag. one number drives width
                // and colour together, which keeps the two from disagreeing.
                activation: (1 - (current - i).abs()).clamp(0.0, 1.0),
                onTap: () => controller.animateToPage(
                  i,
                  duration: AppMotion.base,
                  curve: AppMotion.easing,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.activation, required this.onTap});

  /// 0 = fully inactive, 1 = fully active. fractional while a swipe is in progress.
  final double activation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // the dot is 6px tall, far under the 44px a finger needs, so the tap target is padded around it
      // rather than the dot being drawn bigger than it should look
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: SizedBox(
          width: _PageDots._activeWidth,
          child: Align(
            child: Container(
              height: _PageDots._dotSize,
              width: _PageDots._dotSize +
                  (_PageDots._activeWidth - _PageDots._dotSize) * activation,
              decoration: BoxDecoration(
                // **the inactive end is textFaint, and it used to be hairline** - #ECEEF2 on a #EFF1F5 page is
                // about 1.02 contrast, which is why nobody could tell there was a second page. lerped rather than
                // switched at a threshold: a colour that flips halfway through a drag flickers.
                color: Color.lerp(AppColors.textFaint, AppColors.primaryOrange, activation),
                borderRadius: BorderRadius.circular(_PageDots._dotSize / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One category: the glyph on a grey box, with the name under it. **Two surfaces were tried and
/// both are gone** - a white panel behind all twelve, then a white card per tile.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const double _glyphBox = 64;

  @override
  Widget build(BuildContext context) {
    // a bit more travel than the default: a 3% shrink on a 64px box is barely perceptible
    return PressableScale(
      pressedScale: 0.93,
      onTap: onTap,
      // the grid hands this cell a *tight* height. top-aligned rather than centred: centring drops the
      // glyph box half a line on the tiles whose label wraps, so a row of four wobbles - and which tiles
      // those are changes with the display language.
      child: Column(
        children: [
          // the box stays - it separates one category from the next - but it is neutral: eight pastel fills
          // with matching icon colours read as a children's app.
          //
          // **trackGrey, because a fill is only grey relative to what is behind it**: cardGrey is *lighter*
          // than the page the tile now sits on. no border - hairline is lighter still and would ring a darker
          // fill in a paler line. the glyph is `textMuted`: eight near-black marks in a grid is the heaviest
          // thing on the home screen, and `textGrey` on this fill is under the 3:1 a non-text mark wants.
          Container(
            height: _glyphBox,
            width: _glyphBox,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.trackGrey,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: AppColors.textMuted, size: 27),
          ),
          const SizedBox(height: 7),
          // Expanded, so the label owns the whole strip under the glyph box however many lines it uses - a
          // Text given a tight height paints from the top, keeping first lines on one baseline
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
