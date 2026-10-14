import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import 'package:frontend/core/widgets/pill_search_field.dart';
import '../../data/product_model.dart';
import '../../data/product_section.dart';

/// The one row over a catalogue grid, on a shop's card and on the owner's «Товары» alike: the field
/// the catalogue is searched with, and the disc that opens the sections.
///
/// **There are no section chips.** a scrolling strip of pills plus a «Категории» button under it was
/// the same choice offered twice and cost two rows before the first product. the sheet holds every
/// section with a count each, and the disc goes orange while one is picked.
///
/// A catalogue with one section has nothing to choose between, so the field takes the whole width.
///
/// **The field and the sections are two separate questions**: a catalogue too short to be worth
/// searching can still be split, and then [searchable] is false and the disc is drawn as the
/// «Категории» pill, because an unlabelled disc alone on a line says nothing.
class CatalogueSearchBar extends StatelessWidget {
  const CatalogueSearchBar({
    super.key,
    required this.controller,
    required this.products,
    required this.selected,
    required this.onSelected,
    required this.strings,
    required this.onChanged,
    this.searchable = true,
  });

  final TextEditingController controller;

  /// every row the sheet's counts are about - a typed query must not make them fall
  final List<Product> products;
  final ProductSection? selected;
  final ValueChanged<ProductSection?> onSelected;
  final AppLocalizations strings;
  final ValueChanged<String> onChanged;

  /// False where the caller decided the catalogue is too short to be worth searching - see above.
  final bool searchable;

  /// The field's height, which is also [CircleIconButton.target] - so the disc beside it is centred
  /// on the same line without either one being nudged, and wears [height] as its own diameter: a
  /// 40 disc next to a 44 capsule is two objects rather than one bar.
  static const double height = CircleIconButton.target;

  Future<void> _openSheet(BuildContext context) async {
    final sections = sectionsOf(products);
    final picked = await _SectionSheet.show(
      context,
      strings: strings,
      sections: sections,
      counts: {for (final s in sections) s: products.where((p) => p.section == s).length},
      total: products.length,
      selected: selected,
    );
    if (picked != null) onSelected(picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final hasSections = sectionsOf(products).length > 1;
    final sectionColour = selected == null ? AppColors.textDark : AppColors.primaryOrange;

    if (!searchable) {
      // nothing to search and nothing to pick between: the row would be an empty line of chrome
      if (!hasSections) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: _SectionsButton(
          label: strings.sectionsButton,
          colour: sectionColour,
          onTap: () => _openSheet(context),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: PillSearchField(
            controller: controller,
            height: height,
            // «Поиск» alone next to the disc: the long hint ellipsises in what is left of the line
            hint: hasSections ? strings.searchShortHint : strings.shopProductsSearchHint,
            onChanged: onChanged,
            clearTooltip: strings.searchClear,
          ),
        ),
        if (hasSections) ...[
          const SizedBox(width: 8),
          CircleIconButton(
            icon: LucideIcons.sliders_horizontal,
            tooltip: strings.sectionsButton,
            diameter: height,
            // the one thing left saying a filter is on, now that the chips are gone
            iconColor: sectionColour,
            onTap: () => _openSheet(context),
          ),
        ],
      ],
    );
  }
}

/// The disc with its name on it, for the line where there is no field to sit beside. Same capsule,
/// same height, same orange while a section is picked - it is the disc, labelled.
class _SectionsButton extends StatelessWidget {
  const _SectionsButton({required this.label, required this.colour, required this.onTap});

  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: CatalogueSearchBar.height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sliders_horizontal, size: 17, color: colour),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colour,
                fontSize: 14,
                height: 1.2,
                letterSpacing: -0.1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(LucideIcons.chevron_down, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The full names, with how many products each holds. Pops a one-field record so that picking
/// «Все товары» (null) is told apart from dismissing the sheet (also null).
class _SectionSheet extends StatelessWidget {
  const _SectionSheet({
    required this.strings,
    required this.sections,
    required this.counts,
    required this.total,
    required this.selected,
  });

  final AppLocalizations strings;
  final List<ProductSection> sections;
  final Map<ProductSection, int> counts;
  final int total;
  final ProductSection? selected;

  static Future<(ProductSection?,)?> show(
    BuildContext context, {
    required AppLocalizations strings,
    required List<ProductSection> sections,
    required Map<ProductSection, int> counts,
    required int total,
    required ProductSection? selected,
  }) {
    return showModalBottomSheet<(ProductSection?,)>(
      context: context,
      // the sheet paints its own rounded surface, so the framework's must not sit behind it
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (_) => _SectionSheet(
        strings: strings,
        sections: sections,
        counts: counts,
        total: total,
        selected: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.trackGrey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  strings.sectionsButton,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 21,
                    letterSpacing: -0.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _Row(
                icon: LucideIcons.layout_grid,
                label: strings.sectionAll,
                count: total,
                isSelected: selected == null,
                onTap: () => Navigator.of(context).pop((null,)),
              ),
              for (final section in sections)
                _Row(
                  icon: section.icon,
                  label: section.fullLabel(strings),
                  count: counts[section] ?? 0,
                  isSelected: selected == section,
                  onTap: () => Navigator.of(context).pop((section,)),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primarySoft : AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.primaryOrange : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  height: 1.25,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(
              width: 28,
              child: isSelected
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: Icon(LucideIcons.check, size: 18, color: AppColors.primaryOrange),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
