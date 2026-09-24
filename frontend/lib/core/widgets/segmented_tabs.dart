import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// An iOS-style segmented control: a recessed track with a white pill sliding to the selection.
///
/// Every segment is exactly the same width, taken from the container rather than the text, so the
/// options read as peers - a long label ellipses instead of widening its segment. Past [_fitLimit]
/// segments the track scrolls at a fixed segment width.
///
/// It takes labels, not a domain enum, so one widget serves shop categories and role views.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  /// already localized, and a fixed list: a control that gains segments between two refreshes moves
  /// under the finger reaching for it
  final List<String> labels;

  final int selected;
  final ValueChanged<int> onSelected;

  /// 44 is Apple's minimum touch target and still reads as a filter rather than a row of buttons.
  /// Public because a header that carries this control has to reserve exactly this much room.
  static const double height = 44;

  /// the groove around the pill, and the difference between the two radii below - a concentric inner
  /// corner is `outer - gap`, and getting it wrong is what makes a nested rounded rectangle look melted
  static const double _inset = 4;

  static const double _trackRadius = AppRadius.sm; // 14
  static const double _pillRadius = AppRadius.sm - _inset; // 10

  /// beyond this many segments, even widths get too narrow to read and the control scrolls instead.
  static const int _fitLimit = 4;

  /// wide enough for the longest label in use at this font size without ellipsis
  static const double _scrollingSegmentWidth = 138;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrolls = labels.length > _fitLimit;
        final segmentWidth = scrolls
            ? _scrollingSegmentWidth
            : (constraints.maxWidth - _inset * 2) / labels.length;

        final track = Container(
          height: height,
          width: scrolls ? segmentWidth * labels.length + _inset * 2 : null,
          padding: const EdgeInsets.all(_inset),
          decoration: BoxDecoration(
            color: AppColors.trackGrey,
            borderRadius: BorderRadius.circular(_trackRadius),
          ),
          child: Stack(
            children: [
              // the pill sits *behind* the labels and moves independently, so the transition reads as one
              // object sliding rather than two labels swapping styles
              AnimatedPositioned(
                duration: AppMotion.base,
                curve: Curves.easeOutCubic,
                left: segmentWidth * selected,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(_pillRadius),
                    // `card`, not `raised`: a pill lifted out of a groove a few pixels deep, not floating over the page
                    boxShadow: AppShadows.card,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    SizedBox(
                      width: segmentWidth,
                      child: _Segment(
                        label: labels[i],
                        isActive: i == selected,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

        if (!scrolls) return track;

        return SizedBox(
          height: height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: track,
          ),
        );
      },
    );
  }
}

/// One segment: a label and a hit target. No background of its own - the pill behind it draws the
/// selected state, and a second fill would double up and flash during the transition.
class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque, so the whole segment is tappable and not just the glyphs
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        // the same duration as the pill, so the label darkens as the pill arrives under it
        child: AnimatedDefaultTextStyle(
          duration: AppMotion.base,
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: isActive ? AppColors.textDark : AppColors.textGrey,
            fontSize: 13.5,
            height: 1.1,
            letterSpacing: -0.1,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Padding(
            // keeps a long label off the pill's rounded corners instead of running into them
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
