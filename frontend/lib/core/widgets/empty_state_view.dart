import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The app's one "nothing here" screen. Two nested layers rather than one flat circle, and the
/// inner tile is white and lifted: two tints this pale are indistinguishable on an off-white page.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor = AppColors.primaryOrange,
    this.iconBackground = AppColors.primarySoft,
    this.bottomInset = 0,
  });

  /// Lucide, like every icon here. Behind a bottom-nav tab, use that tab's own glyph.
  final IconData icon;

  final String title;

  /// optional - a title that already says everything should not pad itself out with a second line
  final String? subtitle;

  /// the way out, if there is one. nothing on a permanently empty screen gets a button leading nowhere.
  final Widget? action;

  /// error states colour the icon differently (danger on danger-soft) while keeping the layout
  final Color iconColor;
  final Color iconBackground;

  /// optical rather than mathematical centring - screens under the floating nav bar pass its allowance
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                height: 1.3,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              // capped measure: long help text set to the full screen width is hard to read
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 26),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
