import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The one round control in the app: a glyph inside a white disc with a [AppColors.trackGrey] ring.
///
/// Every header control is built from this - the back chevron on the left, the action on the right -
/// so the two ends of a header are the same object at the same size and weight, and only the glyph's
/// colour says which one is the primary action. A bare icon would have no shape around it on a
/// surface this pale, and would disappear entirely over the shop card's full-bleed cover; the ring
/// is what makes it a control.
///
/// **No outer padding.** Where the disc sits on the page is the header's business, not the button's
/// - see [AppPageHeader]'s gutter constants. The two floating uses pad themselves by [gutterInset].
///
/// [floating] is sitting on a header surface versus hovering over a picture; a third case makes it
/// an enum.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = AppColors.textDark,
    this.tooltip,
    this.floating = false,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// [AppColors.primaryOrange] marks the one action a screen exists for - adding a shop, adding a
  /// product. Everything else stays [AppColors.textDark], including every back button.
  final Color iconColor;

  /// A round button with no label needs one for a screen reader.
  final String? tooltip;

  /// True when the button hovers over content rather than sitting on a header surface.
  final bool floating;

  /// Tap target. Wider than the disc so the touch area clears the 44px accessibility floor.
  static const double target = 44;

  static const double disc = 40;

  /// What a *floating* use pads itself by on the side it hugs: 14 plus the 2 of slack inside the
  /// target puts the disc's edge on the 16px page gutter.
  static const double gutterInset = 14;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: target,
      height: target,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Container(
              width: disc,
              height: disc,
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.trackGrey),
                boxShadow: floating ? AppShadows.floating : AppShadows.card,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The way back out of a pushed screen - [CircleIconButton] with the chevron already in it, so no
/// screen has to name the icon.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, this.onTap, this.floating = false});

  /// Defaults to popping the route. Passed only where "back" means something else.
  final VoidCallback? onTap;

  final bool floating;

  @override
  Widget build(BuildContext context) {
    return CircleIconButton(
      icon: CupertinoIcons.back,
      floating: floating,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
    );
  }
}
