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

    // vertical only: the horizontal gutter is applied by the home screen, which owns it for every
    // block on the feed. this header carried its own copy of the number and the two had to agree by
    // hand, which is how the DOMIX pill ends up a few pixels out of line with the search bar.
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _DomixBrandButton(),
          // Flexible, or this group demands its natural width and the row overflows.
          //
          // _CityChip caps itself at 150px, but a cap is not the same as permission to shrink: on a
          // 360dp phone - the most common android width there is - the pill, the bell and the DOMIX
          // button together were 2px wider than the screen even with the default "Ташкент", and a
          // longer name picked from Nominatim ("Мирзо-Улугбекский район") only made it worse. the
          // two Flexibles hand the shrinking down to the chip's own ellipsis.
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _CityChip(
                    // falls back to the localized default until the user has picked one
                    city: selectedCity ?? strings.cityName,
                    semanticsLabel: strings.changeCityLabel,
                    onTap: () => _pickCity(context),
                  ),
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
          ),
        ],
      ),
    );
  }
}

// pill-shaped rather than on the radius scale on purpose: these are single-line controls, and a
// full stadium is the shape that reads as a chip. the scale governs rectangles - cards, sheets,
// buttons - not this.
//
// **Both controls here lift off the page, and that is what they were missing.** They were flat white
// with a hairline outline - the same recipe as an inert surface - so on a page whose only other
// elements are shadowed cards they read as the palest thing on screen rather than as the two things
// you can press. `AppShadows.card` is the smallest lift in the scale and it is enough: they are 40px
// tall, and anything heavier would put more shadow under a chip than under the VIP cards below it.
// The border stays, since a white shape on a light grey page still needs an edge to be a shape.
const List<BoxShadow> _chipShadow = AppShadows.card;

/// 40, up from 38. Two points is not a style change - it is the same nudge that takes these off
/// Android's 38dp "small control" reading and onto the 40dp both the search bar under them and the
/// nav bar's targets sit on.
const double _chipHeight = 40;

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
              height: _chipHeight,
              decoration: BoxDecoration(
                color: AppColors.surfaceWhite,
                borderRadius: borderRadius,
                border: Border.all(color: AppColors.hairline),
                boxShadow: _chipShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
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
                        // w600: the city is a *value* the user picked, and at w500 it read as a
                        // caption sitting beside the pin rather than as the answer to "where"
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 13,
                          letterSpacing: -0.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    // textMuted, not textFaint: this chevron is the only thing saying the chip opens
                    // something, and at #A9AEB8 on white it was close to invisible
                    const Icon(LucideIcons.chevron_down, color: AppColors.textMuted, size: 14),
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
            height: _chipHeight,
            width: _chipHeight,
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline),
              boxShadow: _chipShadow,
            ),
            child: Center(
              child: Icon(icon, color: AppColors.textDark, size: 18),
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
