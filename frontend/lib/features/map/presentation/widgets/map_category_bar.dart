import 'package:flutter/material.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/segmented_tabs.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

/// The four kinds of shop over the map: one long capsule with a pill sliding inside it.
///
/// **The same control as «Лучшие предложения» on the home screen**, in its floating form: the four
/// categories are one idea, so they are one shape wherever they appear.
///
/// **There is no «Все» segment: the picked one is the way back.** tapping the active category clears
/// the filter, and a fifth segment would take a quarter of the width to say what an empty track
/// already says. the cross on the lit segment (`clearable`) makes that second tap findable.
class MapCategoryBar extends StatelessWidget {
  const MapCategoryBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.strings,
  });

  /// null is every category - see the note above on why that has no segment of its own
  final ShopCategory? selected;
  final ValueChanged<ShopCategory?> onSelected;
  final AppLocalizations strings;

  /// A const list off the enum, so the strip's shape never depends on what the shop list happens to
  /// hold - and a fifth category becomes a fifth segment on the day the enum grows one.
  static const List<ShopCategory> _categories = ShopCategory.values;

  @override
  Widget build(BuildContext context) {
    return SegmentedTabs(
      floating: true,
      clearable: true,
      labels: [for (final category in _categories) category.label(strings)],
      selected: selected == null ? null : _categories.indexOf(selected!),
      // the second tap on the active segment is the "show everything" control
      onSelected: (i) =>
          onSelected(_categories[i] == selected ? null : _categories[i]),
    );
  }
}
