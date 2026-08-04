import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/products/data/product_category.dart';

// Every glyph here is a Lucide icon - one family, one stroke weight, monochrome.
//
// The previous version mixed Hugeicons in, which renders each icon by assembling an SVG string at
// runtime and handing it to flutter_svg. That is strictly worse than a glyph font for this job: it
// dragged in three extra packages, cost a parse per icon, and hinted less crisply at small sizes.
// Lucide ships a real icon font, so the glyphs are vector-hinted, cost nothing to draw, and the
// package was already a dependency. Hugeicons has been removed from pubspec entirely.
//
// The label and the glyph both come off `ProductCategory` rather than being switched over here.
// That is the point of the shared enum: this grid and the product form's category dropdown draw the
// same twelve categories, and a category that looked different depending on which screen you were
// on would be worse than either version alone.
//
// **It is a pager, not a taller grid.** Twelve categories in one static grid meant three rows, and
// the section grew until it dominated the feed. Two rows of four is the shape the home screen was
// designed around, so the extra categories moved onto a second page you swipe to instead of a third
// row you scroll past. That also retired the "Все →" action in the header: the control that reveals
// the rest of the list is now the list itself, and a link promising more of what you can already
// swipe to is a second door to the same room.
//
// **The tiles carry no shop count.** They did briefly - a small pill in the corner saying how many
// shops stocked each category - and it cost a database aggregate on every home load to tell a
// customer something they had not asked. A tile is a way in, not a statistic; the number that
// matters is on the products behind it.
class PopularCategoriesGrid extends StatefulWidget {
  const PopularCategoriesGrid({super.key, required this.onCategoryTap});

  /// Opens the drill-down onto that category's products. Passed in rather than pushed from here so
  /// this widget stays a pure renderer with no route knowledge, which is what lets it be exercised
  /// in a widget test.
  final void Function(ProductCategory category) onCategoryTap;

  @override
  State<PopularCategoriesGrid> createState() => _PopularCategoriesGridState();
}

class _PopularCategoriesGridState extends State<PopularCategoriesGrid> {
  static const int _columns = 4;
  static const int _rows = 2;
  static const int _perPage = _columns * _rows;

  // the content's actual height (64 box + 7 gap + two 13.2px lines) plus a little slack, times two
  // rows plus the gap between them. a constant rather than a childAspectRatio for the reason spelled
  // out at the delegate below.
  static const double _cellHeight = 100;
  static const double _rowGap = 6;
  static const double _pageHeight = _cellHeight * _rows + _rowGap * (_rows - 1);

  late final PageController _controller;

  /// how many pages the twelve categories fill - derived, so adding a thirteenth grows the pager
  /// instead of silently hiding it
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
              // the slice this page shows. clamped at the end because the last page is partial -
              // twelve categories over eight-per-page leaves four on page two.
              final start = page * _perPage;
              final end = math.min(start + _perPage, ProductCategory.values.length);
              final categories = ProductCategory.values.sublist(start, end);

              return GridView.builder(
                // the PageView is the scrollable here; a grid that also scrolled would fight it for
                // the same drag
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  // a fixed row height rather than childAspectRatio, which was the previous
                  // approach. aspect ratio derives height from *width*, so the cell got taller on a
                  // wide phone and shorter on a narrow one - and once the section moved inside a
                  // padded panel the cells narrowed enough that the computed height no longer fit a
                  // two-line label. this is the content's real height plus slack, and it holds on
                  // every screen width. it also fixes the old complaint about tall empty cells,
                  // since the slack is a constant instead of whatever the width happened to imply.
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
        // 4, not the 14 this started at. the dots carry their own vertical touch padding (see
        // _Dot), so the gap the eye measures is that padding *plus* whatever is added here - at 14
        // the panel looked stretched and pushed Лучшие предложения below the fold.
        const SizedBox(height: 4),
        _PageDots(controller: _controller, pageCount: _pageCount),
      ],
    );
  }
}

/// The dots under the pager, driven by the controller's *fractional* page.
///
/// Rebuilding off `onPageChanged` was the simpler option and is what makes most indicators feel
/// cheap: that callback fires once, after the page has already snapped, so the dot jumps a beat
/// behind the finger. Listening to the controller instead means the active pill grows and shrinks
/// continuously as you drag - the indicator tracks the swipe rather than reporting on it
/// afterwards.
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
      // the controller is a Listenable that ticks on every scroll frame, so this rebuilds only the
      // dots - the twelve tiles above are untouched by the animation
      animation: controller,
      builder: (context, _) {
        // `page` is null until the PageView has been laid out once, and `hasClients` is false before
        // it is attached at all - both happen on the very first frame, so fall back to the initial
        // page rather than letting the indicator render with no active dot
        final current = controller.hasClients && controller.page != null
            ? controller.page!
            : controller.initialPage.toDouble();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pageCount; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _Dot(
                // 1 when this page is centred, 0 once a full page away, and everything between
                // while the drag is in flight. one number drives width and colour together, which is
                // what keeps the two from disagreeing mid-swipe.
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
      // the dot itself is 6px tall - far under the 44px minimum a finger needs - so the tap target
      // is padded out around it rather than the dot being drawn bigger than it should look
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
                // lerped rather than switched at a threshold: a colour that flips halfway through a
                // drag is a flicker, a colour that slides is the same motion as the width
                color: Color.lerp(AppColors.hairline, AppColors.primaryOrange, activation),
                borderRadius: BorderRadius.circular(_PageDots._dotSize / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many shops sell this category, as a badge on the tile's corner.
///
/// Brand orange on `primaryTint`, which is the one exception the design tokens allow to "orange is
/// for actions": this is a highlight, and it is the only thing on the grid carrying live data.
/// White border so the pill separates from the tile's own fill where the two overlap.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // a bit more travel than the default: these tiles are small, and a 3% shrink on a 64px box is
    // barely perceptible where the same 3% on a full-width row is plenty
    return PressableScale(
      pressedScale: 0.93,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // the box stays - it is what separates one category from the next - but it is neutral now.
          // eight different pastel fills with eight matching icon colours was the loudest thing on
          // the screen and read as a children's app; a monochrome glyph on an off-white tile reads
          // as a catalogue. cardGrey (not surfaceMuted) on purpose here: surfaceMuted is tuned to sit
          // almost flush with the page background, which is what made the tile read as barely-there.
          //
          Container(
            height: 64,
            width: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cardGrey,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Icon(icon, color: AppColors.textDark, size: 28),
          ),
          const SizedBox(height: 7),
          Flexible(
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
