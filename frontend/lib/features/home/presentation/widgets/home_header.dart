import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _DomixBrandButton(),
          Row(
            children: [
              _CityChip(city: strings.cityName),
              const SizedBox(width: 8),
              const _IconChip(icon: LucideIcons.bell),
            ],
          ),
        ],
      ),
    );
  }
}

// pill-shaped rather than on the radius scale on purpose: these are single-line controls, and a
// full stadium is the shape that reads as a chip. the scale governs rectangles - cards, sheets,
// buttons - not this.
class _CityChip extends StatelessWidget {
  const _CityChip({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.map_pin, color: AppColors.primaryOrange, size: 15),
          const SizedBox(width: 6),
          Text(
            city,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevron_down, color: AppColors.textFaint, size: 13),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      width: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Icon(icon, color: AppColors.textDark, size: 17),
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
    final borderRadius = BorderRadius.circular(AppRadius.sm);

    return Semantics(
      button: true,
      label: 'DOMIX',
      // shrinks under the finger. it used to scale *up* to 1.06 on press, which reads as the button
      // jumping away from the touch rather than yielding to it.
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1,
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: Ink(
            decoration: BoxDecoration(
              // flat brand orange instead of a gradient: at this size the gradient only muddied the
              // colour, and the wordmark is the one place the brand should be unambiguous
              color: AppColors.primaryOrange,
              borderRadius: borderRadius,
              boxShadow: AppShadows.accent(AppColors.primaryOrange),
            ),
            child: InkWell(
              onTap: () {},
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              borderRadius: borderRadius,
              splashColor: Colors.white.withValues(alpha: 0.10),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.boxes, color: Colors.white, size: 17),
                    SizedBox(width: 8),
                    Text(
                      'DOMIX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
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
