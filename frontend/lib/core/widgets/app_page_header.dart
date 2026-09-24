import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';

/// The navigation zone every titled screen in the app wears: a surface of its own carrying the back
/// button, the title and at most one action, with the content as a separate area below it.
///
/// **The separation is tonal, not a line.** [AppColors.surfaceMuted] over [AppColors.background] is
/// a five-to-eight unit step - too small to read as a second colour, big enough that the eye places
/// the edge - and [AppShadows.header] only softens where the two meet. What this replaces was a 1px
/// [AppColors.textFaint] rule, drawn that dark because the two neutrals lighter than it were
/// invisible on a phone in daylight; a surface does the same job without drawing anything, and it
/// does it for the whole header rather than for one edge of it.
///
/// **One widget for both ways a screen is drawn.** A tab inside the shell is a child of an
/// `IndexedStack` with no `Scaffold` of its own, so it cannot hang an `AppBar`; a pushed screen has
/// a Scaffold and wants its header in the `appBar:` slot. This implements [PreferredSizeWidget] for
/// the second case and is an ordinary column child in the first, so the two cannot drift apart -
/// which they had, into four independent headers with three different title sizes between them.
///
/// **Scaffold adds `MediaQuery.padding.top` to [preferredSize] itself**, and the `SafeArea` here is
/// what consumes it. So the reported height is the content's alone, and the surface runs up under
/// the status bar in both modes instead of leaving a strip of page colour above it.
///
/// The status bar style comes with it: with no `AppBar` in the tree nothing else asks for dark
/// icons, and white ones over a surface this pale are invisible.
class AppPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppPageHeader({
    super.key,
    required String this.title,
    this.subtitle,
    this.icon,
    this.showBack = true,
    this.onBack,
    this.action,
    this.bottom,
  }) : child = null;

  /// For the two headers whose middle is a control rather than a title: the search field, and the
  /// deep-link loader that has nothing to put there until the shop arrives.
  const AppPageHeader.custom({
    super.key,
    this.child,
    this.showBack = true,
    this.onBack,
    this.action,
    this.bottom,
  }) : title = null,
       subtitle = null,
       icon = null;

  final String? title;

  /// The line under the title - what the screen is, or what the count on it currently says.
  final String? subtitle;

  /// A tinted glyph tile before the title, for a screen whose subject is a thing rather than a list.
  final IconData? icon;

  /// False on the shell's tabs, which sit on the root route with nothing to pop.
  final bool showBack;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  /// One [CircleIconButton] opposite the title - never two, and never a text button.
  final Widget? action;

  /// Drawn on the header's own surface below the title row, for the part of a screen that belongs to
  /// navigation rather than to content: a filter field, an onboarding progress bar.
  final PreferredSizeWidget? bottom;

  /// The middle of the row when it is not a title - see [AppPageHeader.custom].
  final Widget? child;

  /// Fixed rather than intrinsic, so a header is exactly as tall with a subtitle as without one and
  /// the two tabs beside each other cannot disagree. 48 rather than the round controls' own 44
  /// because the search field [AppPageHeader.custom] carries is 48 - the home feed's bar height,
  /// which is not this header's to change.
  static const double _rowHeight = 48;

  static const double _topPadding = 6;
  static const double _bottomPadding = 10;

  /// Where a disc's slot begins: 14 plus the 2 of slack inside its target lands the disc itself on
  /// the 16px page gutter.
  static const double _discGutter = CircleIconButton.gutterInset;

  /// Where text begins when there is no disc on that side - the gutter the tab headers have always
  /// started their titles on.
  static const double _textGutter = 20;

  /// The gap between a disc and the text beside it.
  static const double _discGap = 8;

  /// The height the header's own content asks for, before the status bar Scaffold adds on top.
  static const double rowExtent = _topPadding + _rowHeight + _bottomPadding;

  @override
  Size get preferredSize => Size.fromHeight(rowExtent + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: _surface(),
    );
  }

  Widget _surface() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        boxShadow: AppShadows.header,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: _topPadding, bottom: _bottomPadding),
              child: SizedBox(height: _rowHeight, child: _row()),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }

  Widget _row() {
    return Row(
      children: [
        if (showBack) ...[
          const SizedBox(width: _discGutter),
          CircleBackButton(onTap: onBack),
          const SizedBox(width: _discGap),
        ] else
          const SizedBox(width: _textGutter),
        if (icon case final glyph?) ...[
          _IconTile(glyph),
          const SizedBox(width: 12),
        ],
        Expanded(child: _swap(_middle())),
        if (action case final trailing?) ...[
          const SizedBox(width: 12),
          _swap(trailing),
          const SizedBox(width: _discGutter),
        ] else
          const SizedBox(width: _textGutter),
      ],
    );
  }

  /// Either the title or whatever [AppPageHeader.custom] was given - keyed on *which*, so a header
  /// whose subtitle merely changed (a count landing) updates in place, and one whose middle changes
  /// kind (a title becoming a search field) animates.
  Widget _middle() {
    if (child case final middle?) {
      return KeyedSubtree(key: const ValueKey('custom'), child: middle);
    }
    if (title case final text?) {
      return KeyedSubtree(
        key: const ValueKey('title'),
        child: _TitleBlock(title: text, subtitle: subtitle),
      );
    }
    // AppPageHeader.custom with nothing to put in the middle: back and air
    return const SizedBox.shrink(key: ValueKey('empty'));
  }

  /// **The whole of the "premium transformation".** A category page's magnifier trades places with
  /// its title, and swapping the two widgets outright is a flicker - one frame of heading, one frame
  /// of field. Crossed over a slide of a few pixels it reads as the title stepping aside for the
  /// field, which is one gesture rather than two states.
  ///
  /// The layout builder is not decoration: [AnimatedSwitcher]'s default one centres its children in
  /// a Stack under *loose* constraints, which would let the search field shrink to the width of its
  /// own hint. `passthrough` hands the row's tight width straight down.
  static Widget _swap(Widget child) {
    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.easing,
      switchOutCurve: AppMotion.easing,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Title and subtitle, centred against the row whether there are one or two lines of it.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // 19 across the whole app. the tabs titled themselves at 22 and the pushed screens at 17
          // and 18, which is three sizes for one thing; this is the size at which a title still
          // leads the row without turning the header into a banner.
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 19,
            height: 1.2,
            letterSpacing: -0.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle case final line?) ...[
          const SizedBox(height: 2),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// The glyph tile before a title - flat tint, the same object a shop card wears in a list.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 20, color: AppColors.primaryOrange),
    );
  }
}
