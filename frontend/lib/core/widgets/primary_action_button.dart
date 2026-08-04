import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The filled orange button an [EmptyStateView] offers as its way out.
///
/// It was `_PrimaryButton`, private to `my_shops_screen.dart`, until the category drill-down needed
/// the identical control for its retry action - the same move `store_form_fields.dart` records for
/// the shared form inputs. Copying it would have been the third orange button in the app with its
/// own idea of the right radius and shadow.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.accent(AppColors.primaryOrange),
      ),
      child: Material(
        color: AppColors.primaryOrange,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 17),
                  const SizedBox(width: 8),
                ],
                // Flexible, not a bare Text: "Добавить новый магазин" and its uzbek equivalent are
                // long enough to overflow a min-sized Row on a narrow screen or at a large text
                // scale. it stays on one line whenever it fits and wraps rather than clipping.
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.25,
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
    );
  }
}
