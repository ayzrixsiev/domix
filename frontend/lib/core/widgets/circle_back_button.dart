import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The way back out of a pushed screen: a chevron inside a white disc.
///
/// Every app bar here is painted [AppColors.background] with no rule under it, so a bare arrow has
/// no shape around it - the ring is what makes it a control, and what keeps it legible over the
/// shop card's full-bleed cover.
///
/// [floating] is sitting in an app bar versus hovering over a picture; a third case makes it an enum.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, this.onTap, this.floating = false});

  /// Defaults to popping the route. Passed only where "back" means something else.
  final VoidCallback? onTap;

  /// True when the button hovers over content rather than sitting in an app bar.
  final bool floating;

  /// What [AppBar.leadingWidth] must be told, or Flutter reserves its own 56 and the title lands at
  /// the wrong distance - a `leading` widget lays out outside the bar's `titleSpacing`.
  static const double leadingWidth = _gutterInset + _target;

  /// 14, not 16: the tap target is 4px wider than the disc on each side, so this puts the *disc's*
  /// left edge on the 16px page gutter.
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
                    // the ring, not the shadow, is what makes this a shape over pale content like the shop cover
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
