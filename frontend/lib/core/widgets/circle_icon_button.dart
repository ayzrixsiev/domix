import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';

/// The one round control in the app: a glyph inside a white disc lifted by a soft shadow.
///
/// Every header control is built from this - the back chevron on the left, the action on the right -
/// so the two ends of a header are the same object at the same size and weight, and only the glyph's
/// colour says which one is the primary action. **No ring**: white on the off-white page is already
/// a shape, and an outline around it is what made the old disc look like a sticker.
///
/// **No outer padding.** Where the disc sits on the page is the header's business, not the button's
/// - see [AppPageHeader]'s gutter constants. The two floating uses pad themselves by [gutterInset].
///
/// **A disc sharing a line with a search field takes that field's height** ([diameter]): the 40
/// that leads a title reads as a different kind of object set down beside a 48px capsule, which is
/// the same reason `MapBarButton` is the field's 50 over the map.
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
    this.diameter,
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

  /// Defaults to [disc]. Passed where the disc shares a line with a search field - see above.
  final double? diameter;

  /// Tap target. Wider than the disc so the touch area clears the 44px accessibility floor.
  static const double target = 44;

  static const double disc = 40;

  /// What a *floating* use pads itself by on the side it hugs: 14 plus the 2 of slack inside the
  /// target puts the disc's edge on the 16px page gutter.
  static const double gutterInset = 14;

  @override
  Widget build(BuildContext context) {
    final size = diameter ?? disc;
    final button = SizedBox(
      // a disc smaller than the floor keeps the floor; a bigger one is its own target
      width: size > target ? size : target,
      height: size > target ? size : target,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                shape: BoxShape.circle,
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
  const CircleBackButton({super.key, this.onTap, this.floating = false, this.diameter});

  /// Defaults to popping the route. Passed only where "back" means something else.
  final VoidCallback? onTap;

  final bool floating;

  /// see [CircleIconButton.diameter]
  final double? diameter;

  @override
  Widget build(BuildContext context) {
    return CircleIconButton(
      icon: CupertinoIcons.back,
      floating: floating,
      diameter: diameter,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
    );
  }
}
