import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/circle_back_button.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/core/widgets/screen_header.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Every category there is, which is what the home grid's eight photographed ones are a front for.
///
/// **Rows with glyphs, not a second grid of photo cards.** Four of the twelve have no product shot,
/// and a grid where a third of the cards fall back to a grey square reads as broken artwork rather
/// than as a complete list. One glyph per row is a look that is the same for all twelve, and it is
/// the same glyph the category carries everywhere else in the app.
class AllCategoriesScreen extends StatelessWidget {
  const AllCategoriesScreen({super.key, required this.onCategoryTap});

  /// The home screen owns the route, exactly as it does for the grid - this screen pops first, so
  /// going back from the products lands on the feed rather than on this list.
  final void Function(ProductCategory category) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const CircleBackButton(),
        leadingWidth: CircleBackButton.leadingWidth,
        title: Text(
          strings.allCategories,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        bottom: ScreenHeader.appBarRule(),
      ),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          itemCount: ProductCategory.values.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final category = ProductCategory.values[index];
            return _CategoryRow(
              icon: category.icon,
              label: category.label(strings),
              onTap: () {
                // pop first, then push: see the field doc
                Navigator.of(context).pop();
                onCategoryTap(category);
              },
            );
          },
        ),
      ),
    );
  }
}

/// One row: the category's glyph in a lit grey box, its name, and the chevron that says the row
/// opens something. The box is the same object the grid's tiles used to be built from - a diagonal
/// gradient with a near-white rim, which is what makes a neutral square read as lit rather than flat.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEBEEF3), Color(0xFFD5DBE4)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: Colors.white, width: 1),
              ),
              // textMuted, not textDark: a column of near-black marks is the heaviest thing on the
              // page, and textGrey lands under the 3:1 a non-text mark wants
              child: Icon(icon, color: AppColors.textMuted, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(CupertinoIcons.chevron_forward, color: AppColors.textFaint, size: 15),
          ],
        ),
      ),
    );
  }
}
