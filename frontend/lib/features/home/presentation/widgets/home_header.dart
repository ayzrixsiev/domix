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

  // reuses the add-store map picker and keeps only the city out of the result: one "move the map,
  // not the pin" ux in the app instead of two that drift apart
  Future<void> _pickCity(BuildContext context) async {
    final cityController = context.read<CityController>();

    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result == null) return;

    // the controller decides whether this is actually a change - another street in the same city
    // leaves the pill alone
    cityController.selectCity(result.city);
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final selectedCity = context.watch<CityController>().city;

    // vertical only: the home screen owns the horizontal gutter for every block on the feed
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _DomixBrandButton(),
          // Flexible, or this group demands its natural width and the row overflows. _CityChip caps itself
          // at 150px, but a cap is not permission to shrink: on a 360dp phone the pill, the bell and the
          // DOMIX button were 2px wider than the screen even with the default "Ташкент".
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
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
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

// pill-shaped rather than on the radius scale, which governs rectangles: a full stadium reads as a
// chip.
//
// **Both chips are white and lifted, and lit rather than merely bright** - a grey fill over a grey
// bar over a grey page flattens the top of the screen into one wash and the pills stop reading as
// things you can press:
//
//   - a near-vertical gradient, white at the top easing to [AppColors.surfaceMuted], so the pill has
//     a lit edge and a shaded one instead of one flat fill
//   - **and no shadow at all**: on this page a black shadow at any alpha is a visible grey shape
//     behind a 40px chip, reading as a second box behind it
//   - the hairline is the only thing defining the pill's edge where the gradient meets the page

/// The lit fill both chips share. Kept here rather than repeated, so the round one and the long one
/// cannot drift apart.
const LinearGradient _chipFill = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [AppColors.surfaceWhite, AppColors.surfaceMuted],
);

/// 40, up from 38: off Android's 38dp "small control" reading and onto the 40dp that the search bar
/// under them and the nav bar's targets already sit on.
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
        // city names can be long ("Мирзо-Улугбекский район"); without a ceiling one would push the
        // bell off the header, so the chip caps its width and ellipsizes
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
                gradient: _chipFill,
                borderRadius: borderRadius,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  // the ConstrainedBox above is what makes the Flexible below legal - a Flexible in an unbounded
                  // Row throws
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.map_pin,
                      color: AppColors.primaryOrange,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // w600: the city is a *value* the user picked, and at w500 it read as a caption beside the pin
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 13,
                          letterSpacing: -0.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    // textMuted, not textFaint: this chevron is the only thing saying the chip opens something
                    const Icon(
                      LucideIcons.chevron_down,
                      color: AppColors.textMuted,
                      size: 14,
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
              gradient: _chipFill,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline),
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
    // half the height, so the ends are true semicircles and the chip matches the round icon chips beside it
    final borderRadius = BorderRadius.circular(_chipHeight / 2);

    return Semantics(
      button: true,
      label: 'DOMIX',
      // shrinks under the finger. it used to scale *up*, which reads as jumping away from the touch.
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1,
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: Ink(
            decoration: BoxDecoration(
              // flat brand orange: at this size a gradient only muddied it, and the wordmark should be unambiguous
              color: AppColors.primaryOrange,
              borderRadius: borderRadius,
            ),
            child: InkWell(
              onTap: () {},
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              borderRadius: borderRadius,
              splashColor: Colors.white.withValues(alpha: 0.10),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              // **the wordmark is artwork, not a Text.** DOMIX is a drawn letterform - chamfered D,
              // square O, a V-cut M - that no font on a phone has, so setting it in a typeface
              // would ship a different logo on every handset.
              child: const SizedBox(
                height: _chipHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Image(
                      image: AssetImage('assets/brand/domix_wordmark.webp'),
                      height: 14,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
