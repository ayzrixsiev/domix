import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';

/// The home feed's search bar: a **button that opens [ProductSearchScreen]**, not a field.
///
/// It has been three things now, and the history is the argument for what it is:
///
/// 1. A `Text` widget styled to look like a field - a picture of a search bar that could not be
///    tapped, focused or typed into.
/// 2. A real `TextField` whose `onSubmitted` was an empty closure, because there was no product
///    search endpoint yet: the control behaved like the thing it looked like right up to the moment
///    it was used.
/// 3. A real `TextField` that really searched - and which raised a keyboard the user could not put
///    away. **Nothing on this screen unfocuses on tap**, the system back button pops routes and
///    there was no route to pop, and the feed just scrolled along underneath. Half the app stayed
///    covered until the user left the tab.
///
/// So it is a button again, but an honest one: it opens a screen whose whole job is searching, and
/// where the keyboard has a back button above it. **This is not a return to (1)** - the difference
/// is that this control does exactly what it appears to do when pressed. A field that raises a
/// keyboard it cannot dismiss is a worse lie than a button that navigates.
///
/// It is also where a live search bar would have had to end up anyway: as-you-type results need
/// somewhere to be drawn, and the home feed is already full.
///
/// Stateless now. There is no `TextEditingController` and no `FocusNode` here any more - both moved
/// to the screen, which is the only place that has anything to type into.
class SearchAndLikeBar extends StatelessWidget {
  const SearchAndLikeBar({super.key});

  static const double _height = 48;

  /// **The filter button next to it is gone rather than disabled.** It was a `Container` with
  /// `onTap: () {}` - the same "picture of a button" this bar itself used to be, and the last one
  /// left on the screen. There is nothing to filter a product search by yet (price band, category,
  /// distance all need decisions that have not been made), and a control that looks live and does
  /// nothing is the specific bug this screen has now been fixed for three times. It comes back when
  /// it filters something.
  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final borderRadius = BorderRadius.circular(AppRadius.sm);

    return Semantics(
      button: true,
      label: strings.searchHint,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProductSearchScreen()),
          ),
          child: Ink(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: borderRadius,
              border: Border.all(color: AppColors.hairline),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textFaint, size: 19),
                const SizedBox(width: 10),
                // the hint text, styled exactly as the real field's hint on the screen this opens,
                // so pressing it reads as the same control moving up into that app bar
                Expanded(
                  child: Text(
                    strings.searchHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                    ),
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
