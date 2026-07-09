import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _DomixBrandButton(),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(
                      LucideIcons.map_pin,
                      color: AppColors.primaryOrange,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Ташкент',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevron_down,
                      color: AppColors.textGrey,
                      size: 14,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Icon(
                  LucideIcons.bell,
                  color: AppColors.textDark,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DomixBrandButton extends StatefulWidget {
  const _DomixBrandButton();

  @override
  State<_DomixBrandButton> createState() => _DomixBrandButtonState();
}

class _DomixBrandButtonState extends State<_DomixBrandButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value) return;

    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);

    return Semantics(
      button: true,
      label: 'DOMIX',
      child: AnimatedScale(
        scale: _isPressed ? 1.08 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryOrange, Color(0xFFFF8E3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryOrange.withAlpha(77),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: () {},
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              borderRadius: borderRadius,
              splashColor: Colors.white.withAlpha(28),
              highlightColor: Colors.white.withAlpha(18),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.boxes, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'DOMIX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
