import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import '../../data/product_category.dart';

/// The category picker on the product form: the twelve shared categories, revealed **in place**.
///
/// Three shapes have been tried here and the reasons matter.
///
/// It began as a free-text field, which is what made the column useless as data - two spellings of
/// "Крепёж" were two groups, and no home-screen tile could ever match either.
///
/// It then became a Material `DropdownButtonFormField`, which fixed the data but not the feel: a
/// Material dropdown opens as a menu overlay sized to its longest item, and with twelve rows that is
/// a slab covering most of the screen, floating over the form with no visible relationship to the
/// field that opened it.
///
/// It now expands downward inside the form, the same way the "Управление магазинами" accordion on the
/// profile screen does - a chevron that rotates a quarter turn to point at what it revealed, and an
/// `AnimatedSize` that grows the panel out from under the header. The options push the rest of the
/// form down rather than covering it, so the field you are editing never leaves the page.
class ProductCategoryPicker extends StatefulWidget {
  const ProductCategoryPicker({
    super.key,
    required this.value,
    required this.strings,
    required this.errorText,
    required this.onChanged,
  });

  final ProductCategory? value;
  final AppLocalizations strings;
  final String? errorText;
  final ValueChanged<ProductCategory> onChanged;

  @override
  State<ProductCategoryPicker> createState() => _ProductCategoryPickerState();
}

class _ProductCategoryPickerState extends State<ProductCategoryPicker> {
  bool _isExpanded = false;

  /// anchors the scroll-into-view below. the panel can be taller than what is left of the screen
  /// under the header, so opening it without this would unfurl the list mostly below the fold.
  final _fieldKey = GlobalKey();

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);

    if (!_isExpanded) return;
    // after the frame that starts the expansion, not before it: ensureVisible measures the widget,
    // and at the moment of the tap it is still collapsed to nothing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _fieldKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        // 0 = bring the field's top edge to the top of the viewport, so the list unfurls into the
        // space below it rather than off the bottom of the screen
        alignment: 0,
        duration: AppMotion.base,
        curve: AppMotion.easing,
      );
    });
  }

  void _select(ProductCategory category) {
    setState(() => _isExpanded = false);
    widget.onChanged(category);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value;
    final hasError = widget.errorText != null;

    // orange while open or once chosen: both are states worth pulling the eye to, and it matches
    // what StoreCategoryTile does on the add-store form
    final borderColor = hasError
        ? AppColors.danger
        : (_isExpanded || selected != null ? AppColors.primaryOrange : AppColors.hairline);

    return Column(
      key: _fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header and options share one bordered box, so the revealed list reads as part of the
        // field rather than as a separate card that happens to sit underneath it
        AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easing,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: borderColor,
              width: _isExpanded || selected != null || hasError ? 1.5 : 1,
            ),
          ),
          // the options list must not paint over the box's rounded corners as it slides out
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _PickerHeader(
                selected: selected,
                strings: widget.strings,
                isExpanded: _isExpanded,
                onTap: _toggle,
              ),
              // AnimatedSize measures its child every frame and tweens its own height between the
              // two, so swapping the list for an empty box animates the reveal without hand-rolling
              // an AnimationController. topCenter keeps the growth anchored under the header.
              AnimatedSize(
                duration: AppMotion.base,
                curve: AppMotion.easing,
                alignment: Alignment.topCenter,
                child: _isExpanded
                    ? Column(
                        children: [
                          const Divider(height: 1, thickness: 1, color: AppColors.hairline),
                          for (final category in ProductCategory.values)
                            _CategoryOption(
                              category: category,
                              strings: widget.strings,
                              isSelected: category == selected,
                              onTap: () => _select(category),
                            ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The always-visible row: what is currently chosen, and the chevron that opens the list.
///
/// It shows the chosen category's glyph and its name **once**. The Material dropdown this replaced
/// showed the icon twice - the field had a `prefixIcon`, and the collapsed value was rendered by
/// re-using the selected menu row, which carried its own icon - so a picked category read as two
/// identical glyphs side by side. Here the option rows and this header are separate widgets, so
/// there is nothing to double up.
class _PickerHeader extends StatefulWidget {
  const _PickerHeader({
    required this.selected,
    required this.strings,
    required this.isExpanded,
    required this.onTap,
  });

  final ProductCategory? selected;
  final AppLocalizations strings;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  State<_PickerHeader> createState() => _PickerHeaderState();
}

class _PickerHeaderState extends State<_PickerHeader> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      // a background tint rather than PressableScale here, unlike the add-store tiles: this control
      // is about to change height, and a shrink competing with an expansion reads as a glitch
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easing,
        color: _isPressed ? AppColors.primaryTint : AppColors.surfaceMuted,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        child: Row(
          children: [
            Icon(
              selected?.icon ?? CupertinoIcons.square_grid_2x2,
              color: selected != null ? AppColors.primaryOrange : AppColors.textFaint,
              size: 18,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                selected?.label(widget.strings) ?? widget.strings.pickProductCategoryPrompt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected != null ? AppColors.textDark : AppColors.textFaint,
                  fontSize: 14.5,
                  fontWeight: selected != null ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // a quarter turn, so the forward chevron ends up pointing down at the rows it revealed -
            // the same indicator the profile screen's shop-management accordion uses
            AnimatedRotation(
              turns: widget.isExpanded ? 0.25 : 0,
              duration: AppMotion.base,
              curve: AppMotion.easing,
              child: Icon(
                CupertinoIcons.chevron_forward,
                color: widget.isExpanded ? AppColors.primaryOrange : AppColors.textFaint,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the revealed list: glyph, name, and a tick on the current choice.
class _CategoryOption extends StatefulWidget {
  const _CategoryOption({
    required this.category,
    required this.strings,
    required this.isSelected,
    required this.onTap,
  });

  final ProductCategory category;
  final AppLocalizations strings;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_CategoryOption> createState() => _CategoryOptionState();
}

class _CategoryOptionState extends State<_CategoryOption> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isPressed;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easing,
        color: isActive ? AppColors.primarySoft : AppColors.surfaceWhite,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: Row(
          children: [
            Icon(
              widget.category.icon,
              color: isActive ? AppColors.primaryOrange : AppColors.textGrey,
              size: 17,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.category.label(widget.strings),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? AppColors.primaryOrange : AppColors.textDark,
                  fontSize: 14,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            // only on the current choice - a tick on every row would say nothing
            if (widget.isSelected) ...[
              const SizedBox(width: 10),
              const Icon(
                CupertinoIcons.checkmark_alt,
                color: AppColors.primaryOrange,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One field of a template product, shown as text instead of an input.
///
/// A template row's name, category and unit are the same in every shop of the category - that is
/// what makes two shops comparable on the same basket - so they are not the owner's to change. They
/// are still *shown*, because an edit screen that only says "Цена" gives no way to check you opened
/// the right product.
///
/// Rendered as plain text with a lock chip rather than as a greyed-out disabled TextField: a
/// disabled input still looks like something that ought to accept typing, and the owner discovers
/// it doesn't by trying. This never invites the tap in the first place.
class ProductLockedField extends StatelessWidget {
  const ProductLockedField({
    super.key,
    required this.value,
    required this.icon,
    required this.strings,
  });

  final String value;
  final IconData icon;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textFaint, size: 18),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 14.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.lock_fill, color: AppColors.textFaint, size: 11),
              const SizedBox(width: 4),
              Text(
                strings.templateFieldLocked,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
