import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';

/// The home feed's search bar: a **button that opens [ProductSearchScreen]**, not a field.
///
/// It was a real `TextField` twice, and both times raised a keyboard the user could not put away -
/// nothing on this screen unfocuses on tap, and there was no route to pop.
class SearchAndLikeBar extends StatelessWidget {
  const SearchAndLikeBar({super.key});

  static const double _height = 48;

  /// **The filter button next to it is gone rather than disabled.** There is nothing to filter a
  /// product search by yet, and a control that looks live and does nothing is the specific bug this
  /// screen has now been fixed for three times. It comes back when it filters something.
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
            // **a recessed grey field, not a white card**: white with a hairline and a lift is what every
            // *content* card on this feed wears, so the one control at the top read as the first row of it.
            //
            // `trackGrey` and not `surfaceMuted` or `cardGrey`, which are at or above the page - a box filled
            // with either reads as white sitting on grey. no border and no shadow with it.
            decoration: BoxDecoration(
              color: AppColors.trackGrey,
              borderRadius: borderRadius,
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 19),
                const SizedBox(width: 10),
                // styled exactly as the real field's hint on the screen this opens, so pressing it reads as the
                // same control moving up into that app bar
                Expanded(
                  child: Text(
                    strings.searchHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // a step darker than the `textFaint` it was: a hint already pale on white is unreadable on a well
                    style: const TextStyle(
                      color: AppColors.textGrey,
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
