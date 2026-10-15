import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/segmented_tabs.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/home/presentation/widgets/home_shop_row.dart';

/// "Лучшие предложения" - the cheapest shops, one tab per shop category.
///
/// **Tabbed rather than one list, because a price comparison is only meaningful inside a category**:
/// stacking the badges in one column would invite 4% to be compared against 6% off two baselines.
///
/// The ranking happens in Postgres; this widget renders the order it is handed. **The strip is always
/// all four categories** and each tab holds [slotCount] places.
class BestOffersList extends StatefulWidget {
  const BestOffersList({super.key, required this.groups, this.onShopTap});

  /// **Mirrors `bestOffersLimit` in the Go handler**, which decides how many shops actually arrive;
  /// this decides how many rows are drawn. The app never truncates what it was sent, so the two
  /// disagreeing costs an extra row rather than a hidden shop.
  static const int slotCount = 15;

  /// The rankings the server actually sent. **This is not the tab strip**, which is always all four
  /// [ShopCategory] values; this only decides what is *inside* a tab. An empty tab says "no shop of
  /// this kind has finished pricing yet", and the strip stops changing shape between refreshes.
  final List<CategoryOffers> groups;

  /// passed down to every row rather than handled here, so navigation stays out of the leaf widgets
  final ValueChanged<Shop>? onShopTap;

  @override
  State<BestOffersList> createState() => _BestOffersListState();
}

class _BestOffersListState extends State<BestOffersList> {
  /// **The strip is the four shop categories, not whatever came back** - a `const` list off the enum,
  /// so the control's shape is independent of the response and nothing moves while a refresh is in
  /// flight. A fifth category becomes a fifth segment the moment the enum grows one.
  static const List<ShopCategory> _categories = ShopCategory.values;

  int _selected = 0;

  /// A linear scan over at most four entries, per frame, rather than a map built in
  /// `didUpdateWidget` - four comparisons cost less than keeping a cache honest across a refresh.
  List<HomeShopPreview> _shopsIn(ShopCategory category) {
    for (final group in widget.groups) {
      if (group.category == category) return group.shops;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    // no clamp needed: the strip is a constant, so `_selected` can only be an index this list has
    final shops = _shopsIn(_categories[_selected]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // drawn unconditionally, including against the empty database the app launches on: the strip is
        // the section's own table of contents, not a filter that appears once there is something to filter
        SegmentedTabs(
          labels: [for (final category in _categories) category.label(strings)],
          selected: _selected,
          onSelected: (i) => setState(() => _selected = i),
        ),
        const SizedBox(height: 12),
        // rebuilt per frame rather than cached: fifteen references over a list the controller already
        // holds, and caching it would mean deciding when it goes stale
        for (final (i, slot) in rankedSlots(
          shops,
          slotCount: BestOffersList.slotCount,
        ).indexed) ...[
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
