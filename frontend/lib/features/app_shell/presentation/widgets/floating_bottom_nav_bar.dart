import 'dart:ui';

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
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(15, 23, 42, 0.18),
              blurRadius: 32,
              spreadRadius: -4,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.64),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.82),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  for (var index = 0; index < items.length; index++)
                    _NavButton(
                      item: items[index],
                      isActive: index == currentIndex,
                      onTap: () => onItemSelected(index),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final ShellNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemColor = isActive
        ? AppColors.primaryOrange
        : const Color(0xFF667085);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 56,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color.fromRGBO(255, 111, 0, 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                border: isActive
                    ? Border.all(
                        color: const Color.fromRGBO(255, 111, 0, 0.18),
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, color: itemColor, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: itemColor,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
