import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/widgets/glass_surface.dart';

class ShellNavItem {
  const ShellNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The shell's tab bar: a pane of glass floating over whichever tab is open.
///
/// **It is glass because the shell sets `extendBody: true`** and every tab leaves 96 of padding at
/// its foot, so the feed, the grid and the map all pass underneath it. That is the only reason a
/// blur earns its cost here - over a page that did not move it would be [AppColors.surfaceRaised]
/// drawn the expensive way.
class FloatingBottomNavBar extends StatelessWidget {
  const FloatingBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onItemSelected,
  });

  final List<ShellNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onItemSelected;

  static const double _height = 76;

  @override
  Widget build(BuildContext context) {
    // Scaffold does not inset a custom bottomNavigationBar, so without this the bar's lowest 48px sit
    // behind a phone's three navigation buttons and half of every touch target is swallowed.
    // viewPadding rather than padding: padding collapses to zero while the keyboard is open.
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;
    final radius = BorderRadius.circular(AppRadius.lg);

    // 22, set against the home feed's 16dp gutter: a floating bar has to read as visibly narrower than
    // the page under it, and at 18 the two edges were 2dp apart and read as one flush block
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 8 + systemInset),
      child: DecoratedBox(
        // outside the clip, or it would be cut off with everything else the glass crops. warm-black
        // rather than neutral: a grey shadow on a warm ground is the cheapest-looking thing an
        // interface can do.
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x262A2018),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
            // a tight second layer, so the bar does not read as floating too high
            BoxShadow(
              color: Color(0x0F2A2018),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: GlassSurface(
          borderRadius: radius,
          child: SizedBox(
            height: _height,
            child: Stack(
              children: [
                _ActivePill(count: items.length, index: currentIndex),
                Row(
                  children: [
                    for (var index = 0; index < items.length; index++)
                      _NavButton(
                        item: items[index],
                        isActive: index == currentIndex,
                        onTap: () => onItemSelected(index),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The orange capsule under the open tab. Solid rather than tinted: orange is what the whole app
/// uses to mean "this is the live one", and a translucent version of it on frosted glass does not
/// carry a white label.
class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment(count == 1 ? 0 : -1 + (2 * index) / (count - 1), 0),
      child: FractionallySizedBox(
        widthFactor: 1 / count,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryOrange,
                  AppColors.primaryOrange.withValues(alpha: 0.85),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryOrange.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final ShellNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // textMuted rather than textGrey for the idle tabs: the glass lightens whatever it sits on, so
    // the step the old opaque bar needed is a step too little here
    final itemColor = widget.isActive
        ? AppColors.textLight
        : AppColors.textMuted;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? 0.90 : 1.0,
          child: SizedBox(
            height: FloatingBottomNavBar._height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  scale: widget.isActive ? 1.08 : 1.0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      widget.item.icon,
                      key: ValueKey(widget.isActive),
                      color: itemColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    color: itemColor,
                    fontSize: 10,
                    fontWeight: widget.isActive
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
