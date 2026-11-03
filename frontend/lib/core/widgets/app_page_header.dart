import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';

/// The header every titled screen wears: back disc, title with an optional subtitle, at most one
/// action.
///
/// **It sits flat on the page, in the page's own colour, with no surface and no shadow of its own**: a
/// band of a second colour with a shadow under it reads as a toolbar bolted onto the screen.
///
/// **One widget for both ways a screen is drawn.** A tab inside the shell has no `Scaffold` and cannot
/// hang an `AppBar`; a pushed screen wants its header in the `appBar:` slot. This implements
/// [PreferredSizeWidget] for the second case and is a column child in the first, so they cannot drift.
///
/// **Scaffold adds `MediaQuery.padding.top` to [preferredSize] itself** and the `SafeArea` here
/// consumes it, so the reported height is the content's alone. The status bar style comes with it.
/// Everything [AppPageHeader.searchable] needs, in one object: the header's other constructors
/// would otherwise each carry seven null fields.
class HeaderSearch {
  const HeaderSearch({
    required this.open,
    required this.field,
    required this.onOpen,
    required this.onClose,
    required this.openTooltip,
    required this.closeTooltip,
    this.resultsAreSearch = false,
  });

  /// Whether the field has the header. The header animates *towards* this - it never jumps.
  final bool open;

  /// The caller's own field, which owns the controller and the focus node. Drawn at
  /// [CircleIconButton.disc] tall, because a circle can only grow into a capsule of its own height.
  final Widget field;

  final VoidCallback onOpen;

  /// Puts the field away, and is also what the cross does once a search's results are up: both mean
  /// "back to the page this was".
  final VoidCallback onClose;

  /// True once the screen is showing the answer to a submitted search: the disc is a cross rather
  /// than a magnifier, since undoing that is the only thing left to do.
  final bool resultsAreSearch;

  final String openTooltip;
  final String closeTooltip;
}

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
  }) : child = null,
       search = null;

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
       icon = null,
       search = null;

  /// **A page that searches itself.** The title keeps its magnifier, and the magnifier *becomes*
  /// the field - see [_searchRow] for why that is one animation rather than two headers.
  const AppPageHeader.searchable({
    super.key,
    required String this.title,
    this.subtitle,
    required HeaderSearch this.search,
    this.bottom,
  }) : icon = null,
       showBack = true,
       onBack = null,
       action = null,
       child = null;

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

  /// Drawn under the title row, for the part of a screen that belongs to navigation rather than to
  /// content: a filter field, an onboarding progress bar.
  final PreferredSizeWidget? bottom;

  /// The middle of the row when it is not a title - see [AppPageHeader.custom].
  final Widget? child;

  /// Non-null only on [AppPageHeader.searchable].
  final HeaderSearch? search;

  /// Fixed rather than intrinsic, so a header is exactly as tall with a subtitle as without one and
  /// the two tabs beside each other cannot disagree. 48 rather than the round controls' own 44
  /// because the search field [AppPageHeader.custom] carries is 48 - the home feed's bar height,
  /// which is not this header's to change.
  static const double _rowHeight = 48;

  static const double _topPadding = 6;
  static const double _bottomPadding = 10;

  /// **The discs on a header whose middle is a control match that control, not the title's 40.** A
  /// 40 disc beside the 48 search field read as a different object dropped next to it; the search
  /// screen's back button looked like the smaller, lesser half of its own bar. An `action` on such
  /// a header is the caller's to size, with this.
  static const double customDisc = _rowHeight;

  /// 40 under a title, the row's own height beside a control - see [customDisc].
  double get _discDiameter =>
      child == null ? CircleIconButton.disc : customDisc;

  /// Where a disc's slot begins, so the disc itself lands on the 16px page gutter: a disc narrower
  /// than its tap target is already inset by that slack, and only the rest is padding.
  double get _discGutter {
    final slack = (CircleIconButton.target - _discDiameter) / 2;
    return slack > 0 ? 16 - slack : 16;
  }

  /// Where text begins when there is no disc on that side - the gutter the tab headers have always
  /// started their titles on.
  static const double _textGutter = 20;

  /// The gap between a disc and the text beside it.
  static const double _discGap = 8;

  /// The height the header's own content asks for, before the status bar Scaffold adds on top.
  static const double rowExtent = _topPadding + _rowHeight + _bottomPadding;

  @override
  Size get preferredSize =>
      Size.fromHeight(rowExtent + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: _surface(),
    );
  }

  Widget _surface() {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: _topPadding,
                bottom: _bottomPadding,
              ),
              child: SizedBox(
                height: _rowHeight,
                child: search == null ? _row() : _searchRow(search!),
              ),
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
          SizedBox(width: _discGutter),
          CircleBackButton(onTap: onBack, diameter: _discDiameter),
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
          SizedBox(width: _discGutter),
        ] else
          const SizedBox(width: _textGutter),
      ],
    );
  }

  /// **The magnifier is not swapped for a field, it becomes one**: two objects taking turns read as a
  /// panel dropping in rather than as a control opening. the disc stretches left into the field and
  /// the glyph that was the button ends up being the field's own.
  ///
  /// the whole morph is a width - a 40px circle and a 40px capsule share a radius, so no corner has to
  /// animate. [TweenAnimationBuilder] rather than a controller, because a header is rebuilt by its
  /// screen rather than driven by it, so `open` flipping mid-flight resumes from where it got to.
  Widget _searchRow(HeaderSearch search) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: search.open ? 1 : 0),
      duration: AppMotion.base,
      curve: AppMotion.easing,
      builder: (context, t, _) => LayoutBuilder(
        builder: (context, constraints) =>
            _searchStack(search, t, constraints.maxWidth),
      ),
    );
  }

  /// Laid out by hand, in the same gutters [_row] uses, so the title does not shift by a pixel when
  /// a screen gains a search and the capsule's own edges land on the page's 16px margin.
  Widget _searchStack(HeaderSearch search, double t, double width) {
    const capsule = CircleIconButton.disc;
    // the slack inside a tap target that is wider than its disc - what puts a 40 disc on the gutter
    const slack = (CircleIconButton.target - capsule) / 2;

    // where the field ends up, and where the disc it grew out of started
    final fieldLeft = _discGutter + CircleIconButton.target + _discGap;
    final sourceLeft = width - _discGutter - slack - capsule;
    final left = sourceLeft + (fieldLeft - sourceLeft) * t;
    // the right edge never moves: it is the page gutter in both states
    final capsuleWidth = width - _discGutter - slack - left;

    // gone well before the capsule's edge reaches it: a capsule sliding over live text is what
    // reads as a panel landing on the heading rather than as the heading making room
    final titleT = (1 - t / 0.3).clamp(0.0, 1.0);

    return Stack(
      children: [
        Positioned(
          left: _discGutter,
          top: 0,
          bottom: 0,
          // the way out of the field is where the way out of the page was. the glyph changes at the
          // halfway point, under a capsule in full flight, which is the one moment nobody is
          // looking at a 20px chevron
          child: Center(
            child: t > 0.5
                ? CircleIconButton(
                    key: const ValueKey('close-search'),
                    icon: Icons.close_rounded,
                    tooltip: search.closeTooltip,
                    onTap: search.onClose,
                  )
                : const CircleBackButton(),
          ),
        ),
        // **gone from the tree, not merely transparent**, once the field has the header: an
        // invisible heading a screen reader still reads is a header saying two things at once
        if (titleT > 0)
          Positioned(
            left: fieldLeft,
            right: _discGutter + CircleIconButton.target + 12,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: titleT < 1,
              child: Opacity(
                opacity: titleT,
                // a few pixels left as it goes, so it reads as stepping aside rather than blinking out
                child: Transform.translate(
                  offset: Offset(-10 * (1 - titleT), 0),
                  child: _TitleBlock(title: title!, subtitle: subtitle),
                ),
              ),
            ),
          ),
        Positioned(
          left: left - slack,
          width: capsuleWidth + slack * 2,
          top: 0,
          bottom: 0,
          child: Center(child: _morph(search, t, capsuleWidth)),
        ),
      ],
    );
  }

  /// At rest this is the ordinary header disc - ink, tooltip and all, in exactly the pixels [_row]
  /// would have put it in. The hand-drawn capsule only exists while the morph is in flight.
  Widget _morph(HeaderSearch search, double t, double capsuleWidth) {
    if (t == 0) {
      return CircleIconButton(
        // the two keys the chrome tests reach for, and the glyph each of them names
        key: ValueKey(search.resultsAreSearch ? 'close-search' : 'open-search'),
        icon: search.resultsAreSearch
            ? Icons.close_rounded
            : LucideIcons.search,
        tooltip: search.resultsAreSearch
            ? search.closeTooltip
            : search.openTooltip,
        onTap: search.resultsAreSearch ? search.onClose : search.onOpen,
      );
    }

    // the field's contents arrive only once there is room for them, and the stand-in hands over as
    // they do: both magnifiers sit 18px from the same edge, so the crossfade is invisible
    final fieldT = ((t - 0.55) / 0.45).clamp(0.0, 1.0);

    return SizedBox(
      height: CircleIconButton.disc,
      width: capsuleWidth,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: 1 - fieldT, child: _standIn(t)),
          // mounted for the whole flight, in both directions: the field has to exist before the
          // screen can focus it on the way in, and still exist while it shrinks on the way out
          Opacity(
            opacity: fieldT,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: search.field,
            ),
          ),
        ],
      ),
    );
  }

  /// The disc on its way to being the field: one white surface with one glyph riding its left edge,
  /// from the middle of a 40px circle to the field's own 18px inset.
  Widget _standIn(double t) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppShadows.card,
          ),
        ),
        Positioned(
          left: 10 + 8 * t,
          top: 0,
          bottom: 0,
          child: Center(
            child: Icon(
              LucideIcons.search,
              // a header glyph is 20 and the field's is 18, so it settles as it travels
              size: 20 - 2 * t,
              color: Color.lerp(AppColors.textDark, AppColors.textMuted, t),
            ),
          ),
        ),
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

  /// What a header's middle does when it changes *kind* - a loader's empty row becoming a shop's name.
  /// swapping outright is a flicker; crossed over a few pixels of slide it reads as one arriving in the
  /// other's place.
  ///
  /// the layout builder is not decoration: [AnimatedSwitcher]'s default centres children under *loose*
  /// constraints, which lets a control shrink to its own contents. `passthrough` hands the row's tight
  /// width straight down.
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
          // one size across the whole app: large enough to lead the row, small enough that a
          // subtitle still fits under it inside the fixed row height
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 21,
            height: 1.15,
            letterSpacing: -0.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle case final line?) ...[
          const SizedBox(height: 3),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              height: 1.2,
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
