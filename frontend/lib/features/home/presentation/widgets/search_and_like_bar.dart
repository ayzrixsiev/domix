import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pill_search_field.dart';
import 'package:frontend/features/home/presentation/screens/product_search_screen.dart';

/// The home feed's search bar: a **button that opens [ProductSearchScreen]**, not a field.
///
/// It was a real `TextField` twice, and both times raised a keyboard the user could not put away -
/// nothing on this screen unfocuses on tap, and there was no route to pop.
class SearchAndLikeBar extends StatelessWidget {
  const SearchAndLikeBar({super.key});

  static const double _height = PillSearchField.pageHeight;

  /// **The filter button next to it is gone rather than disabled.** There is nothing to filter a
  /// product search by yet, and a control that looks live and does nothing is the specific bug this
  /// screen has now been fixed for three times. It comes back when it filters something.
  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    // the capsule PillSearchField wears: this is a picture of that field, so it is that field's shape
    final borderRadius = BorderRadius.circular(999);

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
            padding: const EdgeInsets.only(left: 18, right: 10),
            // **white and flat, with no ring and no shadow.** A grey well is the one muddy patch
            // on this page, and white is what the eye reads as "type here"; the card shadow read as
            // a grey smudge caught in the capsule's corners. Exactly the field it opens on
            // ProductSearchScreen wears, so pressing it reads as the same control moving up.
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: borderRadius,
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.search,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 10),
                // styled exactly as the real field's hint on the screen this opens, so pressing it reads as the
                // same control moving up into that app bar
                Expanded(
                  child: Text(
                    strings.searchHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
