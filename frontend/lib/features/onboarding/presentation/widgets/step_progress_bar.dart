import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// One short bar per step, filled up to the step being shown - how many are left, read at a glance.
///
/// **Segments rather than one continuous bar**: 50% says "half done" without saying half of *what*,
/// where four segments say there are four things and you are on the second. the fill animates, so
/// advancing is visible even when the step's content changes completely underneath it.
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.semanticsLabel,
  });

  /// Zero-based: 0 fills the first segment.
  final int currentStep;
  final int totalSteps;

  /// «Шаг 2 из 4» - the bar is decorative to a screen reader without it.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      value: '${currentStep + 1}/$totalSteps',
      child: Row(
        children: [
          for (var i = 0; i < totalSteps; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.easing,
                height: 4,
                decoration: BoxDecoration(
                  // trackGrey is the token for something sitting on the page background; a filled
                  // segment is brand orange because finishing a step is progress the user made
                  color: i <= currentStep ? AppColors.primaryOrange : AppColors.trackGrey,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
