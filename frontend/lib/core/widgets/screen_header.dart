import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';

/// The title block a tab names itself with, top left: a heading, a line of what the screen is, and
/// a real edge under both.
///
/// **Not an `AppBar`.** Inside the shell every tab is one child of an `IndexedStack` with no
/// `Scaffold` of its own, so an AppBar would need a Scaffold per tab and would still be drawn
/// differently in the two modes each screen supports. Drawn here it is the same header either way.
///
/// **The rule is one plain inset line, in [AppColors.textFaint].** Getting it visible took several
/// passes: [AppColors.hairline] is `#ECEEF2` on a `#EFF1F5` page and [AppColors.trackGrey] is
/// `#E4E7EC` - three units and eleven units of difference, both of which read as nothing on a phone
/// in daylight. The answer was a darker line rather than a cleverer shape.
///
/// [showRule] turns it off for a screen that has its own structure underneath the title - the
/// onboarding flow has a progress bar one gap below, and a rule between the two is a second
/// horizontal line doing the first one's job.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.showRule = true,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 0),
  });

  final String title;
  final String subtitle;

  /// Sits opposite the title, vertically centred against the two lines - the progress counter on
  /// onboarding, and nothing at all on the tabs.
  final Widget? trailing;

  /// Whether to draw the rule under the title - see the class doc.
  final bool showRule;

  /// Horizontal values also set where the rule below starts and stops, so the two cannot drift.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: padding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 22,
                        letterSpacing: -0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5),
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
        ),
        if (showRule) ...[
          const SizedBox(height: 13),
          Padding(
            // inset to the header's own horizontal padding, so the rule begins under the first
            // letter of the title and ends under the last column of the row above it
            padding: EdgeInsets.symmetric(horizontal: padding.left),
            child: const SizedBox(
              height: 1,
              child: ColoredBox(color: AppColors.textFaint),
            ),
          ),
        ],
      ],
    );
  }
}
