import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// One choosable role: an icon tile, a name, a line of what it does here, and a radio.
///
/// A full-width row rather than a square in a grid - three squares divide the width into thirds,
/// where «Владелец магазина» wraps and its subtitle has no room. Selection is carried by tint,
/// border *and* a filled radio, since a tint this pale is invisible in bright sun.
///
/// [isSelected] null is a third state: a list that commits on tap gets a chevron, not a radio.
class RoleOptionTile extends StatelessWidget {
  const RoleOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  /// Null on a list that acts on the tap instead of holding a choice - see the class doc.
  final bool? isSelected;

  final VoidCallback onTap;

  bool get _selected => isSelected ?? false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easing,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _selected ? AppColors.primarySoft : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: _selected ? AppColors.primaryOrange : AppColors.hairline,
              width: _selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // the tile stays one step lighter than whatever it sits on, so the glyph never sinks into the row
                  color: _selected ? AppColors.surfaceWhite : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.xs + 2),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: _selected ? AppColors.primaryOrange : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        letterSpacing: -0.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isSelected == null)
                const Icon(LucideIcons.chevron_right, size: 18, color: AppColors.textFaint)
              else
                _Radio(isSelected: isSelected!),
            ],
          ),
        ),
      ),
    );
  }
}

/// drawn rather than Material's `Radio`, which brings its own 48px padding and ripple into a row
/// that is already one tap target
class _Radio extends StatelessWidget {
  const _Radio({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.easing,
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppColors.primaryOrange : AppColors.surfaceWhite,
        border: Border.all(
          color: isSelected ? AppColors.primaryOrange : AppColors.trackGrey,
          width: 1.6,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}
