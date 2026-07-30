import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The app's one "nothing here" screen: a layered icon, a headline, a line of help, and optionally a
/// badge above or an action below.
///
/// This existed as three hand-written copies before it existed as a widget - the tickets tab, the
/// notifications screen and the my-shops list each built the same 96/60/26 stack inline - and they
/// had already drifted: three different gaps under the icon (20, 20, 22), two different line heights
/// on the body text (1.45 and 1.5), and a measure cap on two of them but not the third. Messages
/// would have been a fourth copy. One widget is what actually makes these screens look like the same
/// app, which is the whole point of the treatment.
///
/// The layering is the design decision worth keeping: **two nested layers rather than one flat
/// circle**, and the inner tile is white and lifted rather than a second tint. Two tints this pale
/// are indistinguishable from each other against an off-white page, so the separation has to come
/// from value (white + shadow), not from hue.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    this.action,
    this.iconColor = AppColors.primaryOrange,
    this.iconBackground = AppColors.primarySoft,
    this.bottomInset = 0,
  });

  /// Lucide, like every other icon in the app. Where the screen is behind a bottom-nav tab, use the
  /// **same glyph as that tab** - the bell on notifications, the hard hat on tickets - so arriving
  /// somewhere feels like arriving at the thing you tapped.
  final IconData icon;

  final String title;

  /// one line of "what will show up here". optional, because an empty state whose title already
  /// says everything shouldn't pad itself out with a second sentence.
  final String? subtitle;

  /// small pill above the title, e.g. "Скоро". for screens that are unbuilt rather than merely
  /// empty - it is the difference between "nothing yet" and "not yet".
  final String? badge;

  /// the way out, if there is one. the my-shops list offers "add a shop"; nothing on a permanently
  /// empty screen does, and inventing a button there would be a control that leads nowhere.
  final Widget? action;

  /// error states colour the icon differently (danger on danger-soft) while keeping the layout
  final Color iconColor;
  final Color iconBackground;

  /// lifts the block off the bottom of the screen so it reads as optically centred rather than
  /// mathematically centred - screens under the floating nav bar pass the shell's allowance here
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
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: AppColors.primaryOrange,
                    fontSize: 11,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
              // capped measure: long help text set to the full screen width is hard to read, and is
              // most of why these screens used to feel sparse and unbalanced
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
