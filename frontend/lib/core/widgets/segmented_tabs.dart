import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// An iOS-style segmented control: a recessed track with a white pill sliding to the selection.
///
/// Every segment is exactly the same width, taken from the container rather than the text, so the
/// options read as peers - a long label ellipses instead of widening its segment. Past [_fitLimit]
/// segments the track scrolls at a fixed segment width.
///
/// It takes labels, not a domain enum, so one widget serves shop categories and role views.
///
/// [floating] is the same split [CircleIconButton] makes: a recessed groove on the page, a white
/// capsule over a map - a grey track over map tiles reads as part of the map.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.floating = false,
    this.clearable = false,
  });

  /// already localized, and a fixed list: a control that gains segments between two refreshes moves
  /// under the finger reaching for it
  final List<String> labels;

  /// null is "none of them", and the pill fades out rather than parking on a segment nobody picked.
  /// The map's category filter is the only caller that needs it: with no «Все» segment to land on,
  /// an empty track is what "every shop" looks like.
  final int? selected;

  final ValueChanged<int> onSelected;

  /// Hovering over a map rather than sitting on the page - see the note above.
  final bool floating;

  /// **Draws a cross on the picked segment**, for a control whose second tap on it clears the
  /// selection. Without the cross that gesture is invisible: the map's filter has no «Все» segment
  /// to go back to, so nothing on screen said the way out was the segment already lit up.
  final bool clearable;

  /// 44 is Apple's minimum touch target and still reads as a filter rather than a row of buttons.
  /// Public because a header that carries this control has to reserve exactly this much room.
  static const double height = 44;

  /// the groove around the pill, and the difference between the two radii below - a concentric inner
  /// corner is `outer - gap`, and getting it wrong is what makes a nested rounded rectangle look melted
  static const double _inset = 4;

  /// the floating form's hairline. **A border is laid out inside the box**, so it comes off the room
  /// the segments have - leave it out of the arithmetic below and the row overflows by exactly 2px.
  static const double _borderWidth = 1;

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
        // everything between the track's edge and the segments: the groove, plus the hairline the
        // floating form draws
        final chrome = _inset * 2 + (floating ? _borderWidth * 2 : 0);
        final segmentWidth = scrolls
            ? _scrollingSegmentWidth
            : (constraints.maxWidth - chrome) / labels.length;

        // a capsule when it floats, so the pill inside it reads as a smaller capsule of the same
        // family - the shape is most of what makes the pair look like one object
        final trackRadius = floating ? 999.0 : _trackRadius;
        final pillRadius = floating ? 999.0 : _pillRadius;

        final track = Container(
          height: height,
          width: scrolls ? segmentWidth * labels.length + chrome : null,
          padding: const EdgeInsets.all(_inset),
          decoration: BoxDecoration(
            color: floating ? AppColors.surfaceWhite : AppColors.trackGrey,
            borderRadius: BorderRadius.circular(trackRadius),
            border: floating
                ? Border.all(color: AppColors.hairline, width: _borderWidth)
                : null,
            boxShadow: floating ? AppShadows.floating : null,
          ),
          child: Stack(
            children: [
              // the pill sits *behind* the labels and moves independently, so the transition reads as one
              // object sliding rather than two labels swapping styles
              AnimatedPositioned(
                duration: AppMotion.base,
                curve: Curves.easeOutCubic,
                // parked where it last was while it fades out, so clearing the selection does not
                // also slide the pill back to the first segment on its way to invisible
                left: segmentWidth * (selected ?? 0),
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: AnimatedOpacity(
                  duration: AppMotion.base,
                  curve: AppMotion.easing,
                  opacity: selected == null ? 0 : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // **the one place the brand colour marks a selection rather than an action.**
                      // over a map the strip is the only chrome with a state to show, and a dark
                      // pill was read as a disabled segment rather than the chosen one.
                      color: floating ? AppColors.primaryOrange : AppColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(pillRadius),
                      // `card`, not `raised`: a pill lifted out of a groove a few pixels deep, not floating over the page
                      boxShadow: floating ? null : AppShadows.card,
                    ),
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
                        activeColor: floating ? AppColors.textLight : AppColors.textDark,
                        // the floating form runs a size tighter: it is a filter hovering over a map,
                        // not a section's own heading, and the point it gives back is what lets
                        // «Сантехника» fit a quarter of a 360px screen without an ellipsis
                        dense: floating,
                        showClear: clearable && i == selected,
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
  const _Segment({
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.dense,
    required this.showClear,
    required this.onTap,
  });

  final String label;
  final bool isActive;

  /// read off the pill underneath: white on the floating track's orange pill, dark on the white
  /// one that slides in the groove
  final Color activeColor;

  /// a half-point smaller and tighter against the pill's corners - see the call site
  final bool dense;

  /// the cross that says a second tap lets this segment go - see [SegmentedTabs.clearable]
  final bool showClear;
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
            // **the resting label is dark on a floating track.** textGrey is tuned against our own
            // pale page; over map tiles it reads as switched off, which is what the three unpicked
            // categories looked like.
            color: isActive
                ? activeColor
                : (dense ? AppColors.textDark : AppColors.textGrey),
            fontSize: dense ? 12.5 : 13.5,
            height: 1.1,
            letterSpacing: -0.1,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Padding(
            // keeps a long label off the pill's rounded corners instead of running into them
            padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // **scaleDown rather than an ellipsis.** the cross costs the segment ~15px, and
                // «Сантехника» only just fits a quarter of a 360px screen as it is - half a point
                // of type is cheaper than losing the end of the word the filter is named after.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, maxLines: 1, textAlign: TextAlign.center),
                  ),
                ),
                if (showClear) ...[
                  const SizedBox(width: 3),
                  Icon(LucideIcons.x, size: 12, color: activeColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
