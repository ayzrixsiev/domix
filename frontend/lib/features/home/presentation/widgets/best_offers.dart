import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
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
/// **The strip is always all four shop categories**, whatever the backend sent - see [groups]. Each
/// tab then holds [slotCount] places, filled from the top by whatever shops have qualified, so a
/// category nobody has finished pricing is a segment over fifteen open places rather than a missing
/// segment.
///
/// This was "Магазины рядом с вами", a distance-ordered list. The ranking is now purely by price,
/// with no location input at all, so the rows show no distance: keeping "0.5 км" next to a list
/// that ignores location would imply a proximity guarantee the section does not make.
class BestOffersList extends StatefulWidget {
  const BestOffersList({super.key, required this.groups, this.onShopTap});

  /// How many places each category's ranking holds. **Mirrors `bestOffersLimit` in the Go handler**,
  /// which is what decides how many shops actually arrive; this is what decides how many rows are
  /// drawn. The app never truncates what it was sent (see [rankedSlots]), so the two disagreeing
  /// costs an extra row rather than a hidden shop.
  static const int slotCount = 15;

  /// The rankings the server actually sent - one entry per shop category that has any, already
  /// sorted and trimmed by it.
  ///
  /// **This is not the tab strip.** The strip is [ShopCategory.values], all four, always; this list
  /// only decides what is *inside* a tab. A category the server said nothing about is still a
  /// segment, and opening it shows fifteen open places.
  ///
  /// The opposite rule was in force until 2026-08-20 - one segment per group, no strip at all below
  /// two of them - on the reasoning that a filter offering an option that filters to nothing is a
  /// broken control. What that missed is that this section is a *ranking* and the four categories
  /// are its axis: the strip is the section's own table of contents, so an empty tab says "no shop
  /// of this kind has finished pricing yet", which is a fact worth reading and is exactly what the
  /// open places under it are for. The strip also stops appearing and disappearing as shops qualify,
  /// which is what made the section change shape between two refreshes.
  final List<CategoryOffers> groups;

  /// Opens the shop card. Passed down to every row rather than handled here, so navigation stays out
  /// of the leaf widgets - the same split [ProductTile] uses.
  final ValueChanged<Shop>? onShopTap;

  @override
  State<BestOffersList> createState() => _BestOffersListState();
}

class _BestOffersListState extends State<BestOffersList> {
  /// **The strip is the four shop categories, not whatever came back.** It is a `const` list off the
  /// enum, which is what makes the control's shape independent of the response: the number of
  /// segments, their order and their labels are the same on a fresh install as on a full market, so
  /// nothing about this section moves while a refresh is in flight. A fifth category becomes a fifth
  /// segment here the moment the enum grows one.
  static const List<ShopCategory> _categories = ShopCategory.values;

  int _selected = 0;

  /// The ranking for one category, or nothing if the server sent none.
  ///
  /// A linear scan over at most four entries, per frame, rather than a map built in
  /// `didUpdateWidget` - four comparisons cost less than the bookkeeping that keeps a cache honest
  /// across a refresh.
  List<HomeShopPreview> _shopsIn(ShopCategory category) {
    for (final group in widget.groups) {
      if (group.category == category) return group.shops;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    // no clamp and no didUpdateWidget guard any more: the strip is a constant, so `_selected` can
    // only ever be an index this list has. that a refresh could leave it pointing past the end was
    // the whole hazard of building the tabs out of the response.
    final shops = _shopsIn(_categories[_selected]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // drawn unconditionally, including on the empty database the app launches against. the
        // section is a ranking and these four are its axis, so the strip is the section's own table
        // of contents rather than a filter that appears once there is something to filter.
        _CategoryTabs(
          categories: _categories,
          selected: _selected,
          strings: strings,
          onSelected: (i) => setState(() => _selected = i),
        ),
        const SizedBox(height: 12),
        // the ranking padded out to a fixed number of places. `slots` is rebuilt per frame rather
        // than cached: it is a list of fifteen references over a list the controller already holds,
        // and caching it would mean deciding when it goes stale.
        for (final (i, slot) in rankedSlots(shops, slotCount: BestOffersList.slotCount).indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          if (slot == null)
            EmptyShopRow(strings: strings)
          else
            HomeShopRow(
              shop: slot,
              strings: strings,
              onTap: switch (widget.onShopTap) {
                final ValueChanged<Shop> open => () => open(slot.shop),
                _ => null,
              },
            ),
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
    required this.categories,
    required this.selected,
    required this.strings,
    required this.onSelected,
  });

  /// The segments, in enum order. **Categories rather than the groups they may or may not have** -
  /// this control's shape must not depend on the response, or the section grows and loses segments
  /// between two refreshes while somebody is looking at it.
  final List<ShopCategory> categories;
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
        final scrolls = categories.length > _fitLimit;
        final segmentWidth = scrolls
            ? _scrollingSegmentWidth
            : (constraints.maxWidth - _inset * 2) / categories.length;

        final track = Container(
          height: _height,
          width: scrolls ? segmentWidth * categories.length + _inset * 2 : null,
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
                  for (var i = 0; i < categories.length; i++)
                    SizedBox(
                      width: segmentWidth,
                      child: _Segment(
                        label: categories[i].label(strings),
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
