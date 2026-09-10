import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import '../../data/product_category.dart';

/// The category picker on the product form: the twelve shared categories, revealed **in place**. A
/// Material `DropdownButtonFormField` opens as an overlay sized to its longest item, which with
/// twelve rows is a slab over most of the screen; this expands downward inside the form instead.
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

  /// anchors the scroll-into-view below: the panel can be taller than what is left of the screen, so
  /// opening it without this would unfurl the list mostly below the fold
  final _fieldKey = GlobalKey();

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);

    if (!_isExpanded) return;
    // after the frame that starts the expansion, not before it: ensureVisible measures the widget, and
    // at the moment of the tap it is still collapsed to nothing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _fieldKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        // 0 = bring the field's top edge to the top of the viewport, so the list unfurls into the space
        // below it rather than off the bottom of the screen
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

    // orange while open or once chosen: both are states worth pulling the eye to
    final borderColor = hasError
        ? AppColors.danger
        : (_isExpanded || selected != null ? AppColors.primaryOrange : AppColors.hairline);

    return Column(
      key: _fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header and options share one bordered box, so the revealed list reads as part of the field
        // rather than as a separate card underneath it
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
              // AnimatedSize measures its child every frame and tweens its own height, so swapping the list for
              // an empty box animates the reveal without an AnimationController. topCenter anchors the growth.
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

/// The always-visible row: what is chosen, and the chevron that opens the list. It shows the glyph
/// and name **once** - the Material dropdown this replaced drew the icon twice, since the collapsed
/// value re-used the selected menu row.
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
      // a background tint rather than PressableScale here: this control is about to change height, and
      // a shrink competing with an expansion reads as a glitch
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
            // a quarter turn, so the forward chevron ends up pointing down at the rows it revealed
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

/// One field of a template product, shown as text instead of an input: its name, category and unit
/// are the same in every shop of the category, which is what makes two shops comparable. They are
/// still *shown*, or an edit screen saying only "Цена" gives no way to check the right product is
/// open.
///
/// Plain text with a lock chip rather than a disabled TextField, which still looks like something
/// that ought to accept typing.
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
