import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class FloatingBottomNavBar extends StatelessWidget {
  const FloatingBottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(15, 23, 42, 0.20),
              blurRadius: 34,
              spreadRadius: -4,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: const Color.fromRGBO(15, 23, 42, 0.08),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.72),
                    Color.fromRGBO(255, 255, 255, 0.52),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.92),
                  width: 1.4,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildNavItem(Icons.home_rounded, 'Главная', true),
                    _buildNavItem(LucideIcons.search, 'Поиск', false),
                    _buildNavItem(LucideIcons.map, 'Карта', false),
                    _buildNavItem(
                      LucideIcons.message_square,
                      'Сообщения',
                      false,
                    ),
                    _buildNavItem(LucideIcons.user, 'Профиль', false),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    final itemColor = isActive
        ? AppColors.primaryOrange
        : const Color.fromRGBO(92, 99, 111, 0.88);

    return Expanded(
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive
              ? const Color.fromRGBO(255, 106, 0, 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: isActive
              ? Border.all(color: const Color.fromRGBO(255, 106, 0, 0.16))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: itemColor, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
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
    );
  }
}
