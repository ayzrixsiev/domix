import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The way back out of a pushed screen: a chevron **inside a white disc**, not a bare glyph.
///
/// ## Why a disc
///
/// Every app bar in this app is painted [AppColors.background] with no rule under it - the same
/// off-white as the page it sits over, deliberately, because a titled bar with a hard line under it
/// makes a short screen look like two screens. The cost is that a bare arrow has nothing at all
/// around it: no bar edge, no divider, no shape, so it reads as a glyph dropped onto the page rather
/// than as a control. Reported exactly that way - "стрелка везде просто как будто висит в воздухе".
///
/// A ring plus a very soft lift is what makes it an object. It is also the one shape that stays
/// legible whatever ends up behind it, which matters because the same button is used over the shop
/// card's full-bleed cover, where there is no bar at all.
///
/// ## Two placements, one bool
///
/// [floating] is the difference between sitting *in* an app bar over the page and hovering over a
/// picture. The picture case needs [AppShadows.floating]; using it in an app bar would put a
/// noticeable dark smudge under a control that is only 2 px above a flat page. A second bool is
/// deliberately not on offer here - see `PriceTierBadgeSize` in CLAUDE.md §9 for what happens when a
/// third case turns up: this becomes an enum, not a pair of flags.
///
/// ## Size
///
/// A 40 px disc inside a 44 px tap target. 44 is the minimum both stores ask for, and the disc is
/// deliberately smaller than the target: a 44 px white circle beside a 17 px title is a button
/// competing with the heading next to it. The ripple is clipped to the target, so a press reads as
/// slightly wider than the disc, which is what a press should look like.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, this.onTap, this.floating = false});

  /// Defaults to popping the route. Passed only where "back" means something else.
  final VoidCallback? onTap;

  /// True when the button hovers over content rather than sitting in an app bar.
  final bool floating;

  /// What [AppBar.leadingWidth] must be told, or Flutter reserves its own 56 and the title lands at
  /// the wrong distance. A `leading` widget is laid out *outside* the bar's `titleSpacing`, so this
  /// widget owns its own left inset - `_gutterInset + _target` is the whole box.
  static const double leadingWidth = _gutterInset + _target;

  /// 14, not 16: the tap target is 4 px wider than the disc on each side, so this is what puts the
  /// **disc's** left edge on the 16 px page gutter that the content below it starts on.
  static const double _gutterInset = 14;

  static const double _target = 44;
  static const double _disc = 40;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _gutterInset),
      child: Center(
        child: SizedBox(
          width: _target,
          height: _target,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap ?? () => Navigator.of(context).maybePop(),
              child: Center(
                child: Container(
                  width: _disc,
                  height: _disc,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWhite,
                    shape: BoxShape.circle,
                    // the ring, not the shadow, is what makes this a shape on a white-ish ground -
                    // a soft shadow alone disappears the moment the button is over something pale,
                    // which is exactly where it sits on the shop card's cover
                    border: Border.all(color: AppColors.trackGrey),
                    boxShadow: floating ? AppShadows.floating : AppShadows.card,
                  ),
                  child: const Icon(CupertinoIcons.back, color: AppColors.textDark, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
