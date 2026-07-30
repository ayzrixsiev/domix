import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/stores/data/shop_category.dart';

// the field widgets the forms in this app share: add-store, edit-store, and the single-product
// add/edit form under features/products. they started life private inside add_store_screen.dart;
// once a second form needed the exact same inputs, the choice was copy them or share them, and two
// copies of a text field drift apart the first time one of them gets a padding tweak.

class StoreFormLabel extends StatelessWidget {
  const StoreFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textDark,
        fontSize: 13,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class StoreFormTextField extends StatelessWidget {
  const StoreFormTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.suffixText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? errorText;
  final TextInputType? keyboardType;

  /// filters what can be typed at all, e.g. digits-only for a price. rejecting a character at the
  /// keyboard is kinder than validating it after the fact - what can't be typed can't be wrong.
  final List<TextInputFormatter>? inputFormatters;

  /// unit shown inside the right edge of the field - currently only "сум"/"so'm" on the price
  /// input. it follows the app language, which is the whole reason it is a string here instead of a
  /// currency glyph in the prefix: there is no som symbol in the icon sets we use, and the dollar
  /// sign that used to sit there named the wrong currency in a shop in Tashkent.
  final String? suffixText;

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textDark, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 15, fontWeight: FontWeight.w400),
        errorText: errorText,
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: AppColors.surfaceMuted,
        prefixIcon: Icon(icon, color: AppColors.textFaint, size: 18),
        suffixText: suffixText,
        suffixStyle: const TextStyle(
          color: AppColors.textGrey,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        // an unfocused field is a plain hairline, not a heavy outline - the border only gains
        // weight and colour once the field is actually the one being edited
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );
  }
}

class StoreLocationTile extends StatelessWidget {
  const StoreLocationTile({
    super.key,
    required this.pickedAddress,
    required this.errorText,
    required this.strings,
    required this.onTap,
  });

  final String? pickedAddress;
  final String? errorText;
  final AppLocalizations strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasLocation = pickedAddress != null;
    final borderColor = errorText != null
        ? AppColors.danger
        : (hasLocation ? AppColors.primaryOrange : AppColors.hairline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormTileSurface(
          onTap: onTap,
          borderColor: borderColor,
          isAccented: hasLocation || errorText != null,
          child: Row(
            children: [
              // the icon swaps from a map pin to a filled tick the moment a location exists, and
              // AnimatedSwitcher cross-fades between the two rather than cutting. it is the one
              // moment this control has something to say, so it is worth a beat of motion.
              AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.easing,
                child: Icon(
                  hasLocation ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.map_pin_ellipse,
                  // a key, or AnimatedSwitcher sees "an Icon" both times and never animates - the
                  // widget type is unchanged, only its properties are
                  key: ValueKey(hasLocation),
                  color: hasLocation ? AppColors.primaryOrange : AppColors.textFaint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  pickedAddress ?? strings.pickLocationPrompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasLocation ? AppColors.textDark : AppColors.textFaint,
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: hasLocation ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (hasLocation) ...[
                const SizedBox(width: 10),
                Text(
                  strings.changeLocationButton,
                  style: const TextStyle(
                    color: AppColors.primaryOrange,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                const SizedBox(width: 10),
                const Icon(CupertinoIcons.chevron_forward, color: AppColors.textFaint, size: 14),
              ],
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
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

// the shop-category picker on the add-store form. shaped like StoreLocationTile above rather than
// as a material DropdownButton: both fields are "tap to choose from a list that needs explaining",
// a dropdown menu has no room for the per-category description, and one picker pattern on a form
// beats two that look unrelated.
//
// there is no edit-form counterpart on purpose - the category decided which product template seeded
// the shop's catalogue, so it is fixed once the shop exists.
class StoreCategoryTile extends StatelessWidget {
  const StoreCategoryTile({
    super.key,
    required this.selected,
    required this.errorText,
    required this.strings,
    required this.onTap,
  });

  final ShopCategory? selected;
  final String? errorText;
  final AppLocalizations strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = selected;
    final borderColor = errorText != null
        ? AppColors.danger
        : (category != null ? AppColors.primaryOrange : AppColors.hairline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormTileSurface(
          onTap: onTap,
          borderColor: borderColor,
          isAccented: category != null || errorText != null,
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.easing,
                child: Icon(
                  category != null
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.square_grid_2x2,
                  key: ValueKey(category != null),
                  color: category != null ? AppColors.primaryOrange : AppColors.textFaint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category?.label(strings) ?? strings.pickCategoryPrompt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: category != null ? AppColors.textDark : AppColors.textFaint,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: category != null ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    // the catalogue size is the concrete thing the owner gets out of the
                    // choice, so it stays visible after picking rather than only in the sheet
                    if (category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        strings.readyCatalogLabel(category.templateSize),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(CupertinoIcons.chevron_down, color: AppColors.textFaint, size: 14),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
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

// the sheet StoreCategoryTile opens. a bottom sheet rather than a dialog because each row carries
// two lines of explanation plus the catalogue size, and four of those don't fit an alert box.
//
// returns the picked ShopCategory through Navigator.pop, or null if dismissed.
class ShopCategorySheet extends StatelessWidget {
  const ShopCategorySheet({super.key, required this.selected, required this.strings});

  final ShopCategory? selected;
  final AppLocalizations strings;

  static Future<ShopCategory?> show(
    BuildContext context, {
    required ShopCategory? selected,
    required AppLocalizations strings,
  }) {
    return showModalBottomSheet<ShopCategory>(
      context: context,
      // the sheet paints its own rounded surface, so the framework's must not sit behind it
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (_) => ShopCategorySheet(selected: selected, strings: strings),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
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
                    color: const Color(0xFFE1E4EA),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  strings.shopCategoryPickerTitle,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 19,
                    letterSpacing: -0.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  strings.shopCategoryPickerHint,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              for (final category in ShopCategory.values)
                _CategoryRow(
                  category: category,
                  strings: strings,
                  isSelected: category == selected,
                  onTap: () => Navigator.of(context).pop(category),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.strings,
    required this.isSelected,
    required this.onTap,
  });

  final ShopCategory category;
  final AppLocalizations strings;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primarySoft : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(
                  CupertinoIcons.cube_box_fill,
                  color: isSelected ? AppColors.primaryOrange : AppColors.textFaint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.label(strings),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 15,
                              letterSpacing: -0.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            '${category.templateSize}',
                            style: const TextStyle(
                              color: AppColors.primaryOrange,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      category.description(strings),
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                color: isSelected ? AppColors.primaryOrange : AppColors.hairline,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StoreInlineErrorCard extends StatelessWidget {
  const StoreInlineErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppColors.danger, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// matches the call cta in the shop details sheet: fixed comfortable height, radius from the scale,
// and a soft colour-matched glow instead of material's default grey elevation.
//
// [color] exists so the destructive variant on the edit screen is the same button in red rather
// than a second button class that would drift from this one.
class StoreSubmitButton extends StatelessWidget {
  const StoreSubmitButton({
    super.key,
    required this.label,
    required this.isBusy,
    required this.onTap,
    this.color = AppColors.primaryOrange,
    this.icon,
  });

  final String label;
  final bool isBusy;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // the glow is dropped while busy so the disabled state reads as genuinely inert
        boxShadow: isBusy ? const [] : AppShadows.accent(color),
      ),
      child: Material(
        color: isBusy ? color.withValues(alpha: 0.55) : color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: isBusy ? null : onTap,
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: Center(
              child: isBusy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 17),
                          const SizedBox(width: 9),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              letterSpacing: 0.1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// the destructive counterpart to StoreSubmitButton, used at the bottom of the edit-shop and
// edit-product forms. outlined, not a filled red slab: the strongest-looking control on a page
// should be the one you most likely came to press, and that is "save" - this action gets its weight
// from the confirmation dialog behind it instead.
class StoreDangerButton extends StatelessWidget {
  const StoreDangerButton({
    super.key,
    required this.label,
    required this.isBusy,
    required this.onTap,
    this.icon = CupertinoIcons.trash,
  });

  final String label;
  final bool isBusy;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: isBusy ? null : onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.dangerSoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
          ),
          child: SizedBox(
            height: 50,
            width: double.infinity,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppColors.danger, size: 17),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.danger.withValues(alpha: isBusy ? 0.5 : 1),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// the shop identity strip both the settings hub and the upload screen open with: those screens are
// reached from a list where every row looks alike, and doing the wrong shop's paperwork is annoying
// to undo. [trailing] lets the hub hang a chevron-free stat line off the same block.
class ShopIdentityCard extends StatelessWidget {
  const ShopIdentityCard({
    super.key,
    required this.name,
    required this.subtitle,
    this.trailing,
  });

  final String name;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(CupertinoIcons.building_2_fill, color: AppColors.primaryOrange, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}


// The pressable surface behind StoreLocationTile and StoreCategoryTile.
//
// Both are "tap to choose something on another screen", both looked identical, and both used to be
// a Material + InkWell that gave a faint grey ripple somewhere in the middle of a 15px-padded box.
// On a control this large that reads as nothing happening at all - which is exactly the complaint
// these two got. PressableScale moves the whole tile instead, and the fill deepens for the duration
// of the press, so the feedback is the shape you touched rather than a wash inside it.
class _FormTileSurface extends StatefulWidget {
  const _FormTileSurface({
    required this.child,
    required this.onTap,
    required this.borderColor,
    required this.isAccented,
  });

  final Widget child;
  final VoidCallback onTap;

  /// hairline normally, brand orange once a value is chosen, danger while the field is in error
  final Color borderColor;

  /// whether that border is the emphasised 1.5px one - true once chosen or once wrong, since both
  /// are states the eye should be pulled to
  final bool isAccented;

  @override
  State<_FormTileSurface> createState() => _FormTileSurfaceState();
}

class _FormTileSurfaceState extends State<_FormTileSurface> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Listener rather than another GestureDetector: PressableScale below already owns the tap
      // gesture, and two competing recognisers on the same subtree is how a tap starts getting
      // eaten. this only observes the raw pointer to tint the fill, and never claims anything.
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: PressableScale(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easing,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          decoration: BoxDecoration(
            // primaryTint under the finger: a step towards the brand colour rather than a grey
            // overlay, so the press looks like part of the same design as the orange border
            color: _isPressed ? AppColors.primaryTint : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: widget.borderColor,
              width: widget.isAccented ? 1.5 : 1,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
