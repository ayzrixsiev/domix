import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/presentation/widgets/home_shop_row.dart';

/// "Лучшие предложения" - the cheapest shops, one tab per shop category.
///
/// **Tabbed rather than one list, because a price comparison is only meaningful inside a category.**
/// A Сантехника shop's basket is a different list of goods from a Универсальный shop's, so "на 4%
/// дешевле рынка" refers to a different market on each row. The Basket Price Index makes those rows
/// *sortable* against each other - that is what normalising buys - but stacking the badges in one
/// column would invite the reader to compare 4% against 6% when the two percentages are measured
/// off different baselines.
///
/// The ranking happens in Postgres (`ListBestOffersInCategory`, `ORDER BY price_index ASC`), not
/// here - this widget renders whatever order it is handed. That matters because the ordering is the
/// entire meaning of the section, and a list sorted twice by two different rules is a list that
/// disagrees with itself.
///
/// This was "Магазины рядом с вами", a distance-ordered list. The ranking is now purely by price,
/// with no location input at all, so the rows show no distance: keeping "0.5 км" next to a list
/// that ignores location would imply a proximity guarantee the section does not make.
class BestOffersList extends StatefulWidget {
  const BestOffersList({super.key, required this.groups});

  /// One entry per shop category that has ranked shops, already sorted and trimmed - by the server
  /// for real data, by `home_showcase_content.dart` for the showcase rows. The widget does not know
  /// which, and empty categories never reach it, so there is no such thing as a dead tab.
  final List<CategoryOffers> groups;

  @override
  State<BestOffersList> createState() => _BestOffersListState();
}

class _BestOffersListState extends State<BestOffersList> {
  int _selected = 0;

  @override
  void didUpdateWidget(BestOffersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // the tab list changes shape when a refresh brings back a different set of categories - a
    // category emptying out would otherwise leave _selected pointing past the end of the list
    if (_selected >= widget.groups.length) _selected = 0;
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    if (widget.groups.isEmpty) return const SizedBox.shrink();

    // clamped rather than trusted: didUpdateWidget catches the shrink between builds, but the very
    // first build after a hot reload can arrive with a stale index and `groups[_selected]` would
    // throw rather than degrade
    final index = _selected.clamp(0, widget.groups.length - 1);
    final group = widget.groups[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // one category means nothing to switch between, so the strip is not drawn at all rather
        // than drawn with a single permanently-selected pill. this is the state the app launches
        // in, and a lone tab reads as a control that is broken.
        if (widget.groups.length > 1) ...[
          _CategoryTabs(
            groups: widget.groups,
            selected: index,
            strings: strings,
            onSelected: (i) => setState(() => _selected = i),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < group.shops.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          HomeShopRow(shop: group.shops[i], strings: strings),
        ],
      ],
    );
  }
}

/// The category filter, as an iOS-style segmented control: one recessed track with a white pill
/// that slides to the selected segment.
///
/// **Every segment is exactly the same width**, and the width comes from the container rather than
/// from the text. "Универсальный" is eleven characters and "Обои" is four, so sizing to content
/// would make one segment three times another and leave the control looking like a mistake — the
/// whole point of a segmented control is that the options read as peers. A long label ellipses
/// rather than widening its segment.
///
/// Two layouts from one measurement. Up to [_fitLimit] segments the track divides the available
/// width evenly; beyond that the segments take a fixed width and the whole track scrolls, keeping
/// the same pill, the same height and the same rhythm. There are four shop categories today, so the
/// scrolling branch is not reachable — it is here because a fifth category is a plausible product
/// change and discovering then that the control collapses is a worse time to find out.
///
/// A `TabBar` was the obvious alternative and is the wrong shape: it brings an underline indicator
/// and its own typography, neither of which matches anything else on this screen, and it sizes tabs
/// to their labels.
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.groups,
    required this.selected,
    required this.strings,
    required this.onSelected,
  });

  final List<CategoryOffers> groups;
  final int selected;
  final AppLocalizations strings;
  final ValueChanged<int> onSelected;

  /// 44 sits between a comfortable touch target (44 is Apple's own minimum) and something that
  /// still reads as a filter rather than a row of buttons.
  static const double _height = 44;

  /// the groove around the pill. also the difference between the two radii below - an inner corner
  /// concentric with an outer one is `outer - gap`, and getting that wrong is what makes a nested
  /// rounded rectangle look slightly melted.
  static const double _inset = 4;

  static const double _trackRadius = AppRadius.sm; // 14
  static const double _pillRadius = AppRadius.sm - _inset; // 10

  /// beyond this many segments, even widths get too narrow to read and the control scrolls instead.
  static const int _fitLimit = 4;

  /// how wide a segment is once the control scrolls. wide enough for the longest shop-category
  /// label at this font size without ellipsis.
  static const double _scrollingSegmentWidth = 138;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrolls = groups.length > _fitLimit;
        final segmentWidth = scrolls
            ? _scrollingSegmentWidth
            : (constraints.maxWidth - _inset * 2) / groups.length;

        final track = Container(
          height: _height,
          width: scrolls ? segmentWidth * groups.length + _inset * 2 : null,
          padding: const EdgeInsets.all(_inset),
          decoration: BoxDecoration(
            color: AppColors.trackGrey,
            borderRadius: BorderRadius.circular(_trackRadius),
          ),
          child: Stack(
            children: [
              // the pill is *behind* the labels and moves independently of them, which is what makes
              // the transition read as one object sliding rather than as two labels swapping styles
              AnimatedPositioned(
                duration: AppMotion.base,
                curve: Curves.easeOutCubic,
                left: segmentWidth * selected,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(_pillRadius),
                    // `card`, not `raised`: the pill is lifted out of a groove a few pixels deep,
                    // not floating over the page. a heavier shadow at this size reads as a smudge.
                    boxShadow: AppShadows.card,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < groups.length; i++)
                    SizedBox(
                      width: segmentWidth,
                      child: _Segment(
                        label: groups[i].category.label(strings),
                        isActive: i == selected,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

        if (!scrolls) return track;

        return SizedBox(
          height: _height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: track,
          ),
        );
      },
    );
  }
}

/// One segment: a label and a hit target, and nothing else.
///
/// **No background of its own.** The selected state is drawn by the pill sliding behind it, so a
/// segment that painted its own fill would double up during the transition and flash.
class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque, so the whole segment is tappable and not just the glyphs - a filter you have to hit
      // precisely is a filter people stop using
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        // animates the weight and colour over the same duration as the pill, so the label darkens
        // as the pill arrives under it rather than snapping ahead of it
        child: AnimatedDefaultTextStyle(
          duration: AppMotion.base,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: isActive ? AppColors.textDark : AppColors.textGrey,
            fontSize: 13.5,
            height: 1.1,
            letterSpacing: -0.1,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Padding(
            // keeps a long label off the pill's rounded corners instead of running into them
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
