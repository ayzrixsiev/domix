import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/location/presentation/controllers/city_controller.dart';
import 'package:frontend/features/map/presentation/screens/location_picker_screen.dart';
import 'package:frontend/features/notifications/presentation/screens/notifications_screen.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  // opens the same map picker the add-store form uses, and keeps only the city out of the result.
  // reusing it rather than building a city-only screen means one "move the map, not the pin" ux in
  // the app instead of two that drift apart - the picker already resolves a city for free.
  Future<void> _pickCity(BuildContext context) async {
    final cityController = context.read<CityController>();

    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result == null) return;

    // the controller decides whether this is actually a change: dropping the pin on another street
    // in the same city leaves the pill alone, a different city updates it
    cityController.selectCity(result.city);
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final selectedCity = context.watch<CityController>().city;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _DomixBrandButton(),
          Row(
            children: [
              _CityChip(
                // falls back to the localized default until the user has picked one
                city: selectedCity ?? strings.cityName,
                semanticsLabel: strings.changeCityLabel,
                onTap: () => _pickCity(context),
              ),
              const SizedBox(width: 8),
              _IconChip(
                icon: LucideIcons.bell,
                semanticsLabel: strings.notificationsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
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
  const _CityChip({
    required this.city,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String city;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(19);

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: ConstrainedBox(
        // the label used to be the hardcoded "Ташкент"; it is now whatever nominatim names the
        // picked point, which can be much longer ("Мирзо-Улугбекский район"). without a ceiling a
        // long name would push the bell off the header, so the chip caps its width and ellipsizes.
        constraints: const BoxConstraints(maxWidth: 150),
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: Ink(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                borderRadius: borderRadius,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  // shrink to the label when it is short; the ConstrainedBox above is what makes
                  // the Flexible below legal, since a Flexible in an unbounded Row throws
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.map_pin, color: AppColors.primaryOrange, size: 15),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevron_down, color: AppColors.textFaint, size: 13),
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

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline),
            ),
            child: Center(
              child: Icon(icon, color: AppColors.textDark, size: 17),
            ),
          ),
        ),
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
