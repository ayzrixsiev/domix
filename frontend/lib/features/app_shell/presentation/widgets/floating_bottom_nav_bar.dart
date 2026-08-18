import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';

class ShellNavItem {
  const ShellNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

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

  @override
  Widget build(BuildContext context) {
    // the gesture pill or the three navigation buttons at the bottom of the phone.
    //
    // Scaffold does not inset a custom bottomNavigationBar - flutter's own BottomNavigationBar adds
    // this padding itself, and a hand-rolled one has to do the same. without it the bar is laid out
    // flush with the physical bottom of the screen, so on a phone with three-button navigation its
    // lowest 48px sit *behind* the back/home/recents buttons: the tab labels are covered and the
    // bottom half of every touch target is swallowed by the system before it reaches us.
    //
    // viewPadding rather than padding, because padding collapses to zero while the keyboard is open
    // and the bar would drop into the system buttons for as long as somebody is typing.
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 8 + systemInset),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          // Uniform, single-color border only — safe with borderRadius.
          border: Border.all(
            color: const Color(0xFFEDEEF1),
            width: 1,
          ),
          boxShadow: [
            // Wide, soft ambient shadow for elevation.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            // Tight shadow for grounding, so it doesn't look like it's floating too high.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                items.length == 1
                    ? 0
                    : -1 + (2 * currentIndex) / (items.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / items.length,
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
            ),
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
    final itemColor = widget.isActive ? Colors.white : const Color(0xFF98A2B3);

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
            height: 76,
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
                    fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w600,
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