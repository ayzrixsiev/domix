import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';
import '../../data/product_model.dart';
import '../../data/product_section.dart';

/// Two lines over a shop's grid: the chips, then the «Категории» button under them.
///
/// **The button and the chips are one choice made two ways**: a chip is the quick tap, the button
/// opens the full names with a count each. Both write the same [selected], so there is nothing to
/// keep in step. null is «Все товары».
///
/// The chips get the whole width and scroll, because six names do not fit a phone and wrapping them
/// would push the grid down by a row nobody is reading; the button sits on its own line under them,
/// where the reference puts its filters.
class ProductSectionBar extends StatefulWidget {
  const ProductSectionBar({
    super.key,
    required this.products,
    required this.selected,
    required this.onSelected,
    required this.strings,
    this.gutter = 16,
  });

  /// every row the chips are *about* - the counts come from here, so a search typed over the grid
  /// does not make a chip's number fall
  final List<Product> products;
  final ProductSection? selected;
  final ValueChanged<ProductSection?> onSelected;
  final AppLocalizations strings;

  /// the page gutter: the button starts on it, and the last chip scrolls out past it
  final double gutter;

  /// one row of pills
  static const double rowHeight = 44;

  /// both rows plus the gap between them
  static const double height = rowHeight * 2 + 8;

  @override
  State<ProductSectionBar> createState() => _ProductSectionBarState();
}

class _ProductSectionBarState extends State<ProductSectionBar> {
  final _selectedKey = GlobalKey();

  @override
  void didUpdateWidget(ProductSectionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // a pick made in the sheet can be a chip that is off screen: bring it into view
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _selectedKey.currentContext;
        if (target == null) return;
        Scrollable.ensureVisible(
          target,
          duration: AppMotion.base,
          curve: AppMotion.easing,
          alignment: 0.5,
        );
      });
    }
  }

  Future<void> _openSheet() async {
    final sections = sectionsOf(widget.products);
    final picked = await _SectionSheet.show(
      context,
      strings: widget.strings,
      sections: sections,
      counts: {for (final s in sections) s: widget.products.where((p) => p.section == s).length},
      total: widget.products.length,
      selected: widget.selected,
    );
    if (picked != null) widget.onSelected(picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final sections = sectionsOf(widget.products);
    final total = widget.products.length;

    int countOf(ProductSection section) =>
        widget.products.where((p) => p.section == section).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: ProductSectionBar.rowHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            // the pills' shadows are wider than the row, so the list must not clip them
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: widget.gutter),
            children: [
              _Pill(
                key: widget.selected == null ? _selectedKey : null,
                icon: LucideIcons.layout_grid,
                label: strings.sectionAll,
                count: widget.selected == null ? total : null,
                selected: widget.selected == null,
                onTap: () => widget.onSelected(null),
              ),
              for (final section in sections) ...[
                const SizedBox(width: 8),
                _Pill(
                  key: widget.selected == section ? _selectedKey : null,
                  icon: section.icon,
                  label: section.label(strings),
                  count: widget.selected == section ? countOf(section) : null,
                  selected: widget.selected == section,
                  onTap: () => widget.onSelected(section),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.gutter),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _Pill(
              icon: LucideIcons.sliders_horizontal,
              label: strings.sectionsButton,
              trailing: LucideIcons.chevron_down,
              onTap: _openSheet,
            ),
          ),
        ),
      ],
    );
  }
}

/// The owner's «Товары» header row: the field they search their own catalogue with, and the disc
/// that opens the same section sheet [ProductSectionBar]'s button opens.
///
/// **It replaces the chips rather than sitting above them.** An owner arrives here to find one row
/// out of a hundred, and a scrolling strip of section pills is the wrong first control for that -
/// it costs a row of height to answer a question ("which section?") that the search field answers
/// better. The sheet still holds every section with its count, so nothing was lost; the disc goes
/// orange while a section is picked, which is what the chips were really saying.
class CatalogueSearchBar extends StatelessWidget {
  const CatalogueSearchBar({
    super.key,
    required this.controller,
    required this.products,
    required this.selected,
    required this.onSelected,
    required this.strings,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// every row the sheet's counts are about - a typed query must not make them fall
  final List<Product> products;
  final ProductSection? selected;
  final ValueChanged<ProductSection?> onSelected;
  final AppLocalizations strings;
  final ValueChanged<String> onChanged;

  /// The field's height, which is also [CircleIconButton.target] - so the disc beside it is centred
  /// on the same line without either one being nudged.
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
    // one section is nothing to choose between, so the field takes the whole width
    final hasSections = sectionsOf(products).length > 1;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              // a capsule rather than AppRadius.sm: it is the shape of the disc beside it, and the
              // two read as one control only if they share it
              borderRadius: BorderRadius.circular(999),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.search, color: AppColors.textMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppColors.primaryOrange,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: InputDecoration(
                      // strips the ~48px a TextField reserves for a material label
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: strings.searchShortHint,
                      hintStyle: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                // only while there is something to clear, so the row is quiet until it is being used
                if (controller.text.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(LucideIcons.x, color: AppColors.textMuted, size: 17),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasSections) ...[
          const SizedBox(width: 8),
          CircleIconButton(
            icon: LucideIcons.sliders_horizontal,
            tooltip: strings.sectionsButton,
            // the one thing left saying a filter is on, now that the chips are gone
            iconColor: selected == null ? AppColors.textDark : AppColors.primaryOrange,
            onTap: () => _openSheet(context),
          ),
        ],
      ],
    );
  }
}

/// One pill: white and lifted, or dark when it is the pick. Orange is kept for actions.
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// shown on the picked chip only, so one number is on screen and it is the one in play
  final int? count;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.textLight : AppColors.textDark;

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.easing,
          height: ProductSectionBar.rowHeight - 4,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryDark : AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected ? null : AppShadows.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? AppColors.textLight : AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  height: 1.2,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count case final n?) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.textLight.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      color: AppColors.textLight,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (trailing case final glyph?) ...[
                const SizedBox(width: 6),
                Icon(glyph, size: 16, color: AppColors.textMuted),
              ],
            ],
          ),
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
