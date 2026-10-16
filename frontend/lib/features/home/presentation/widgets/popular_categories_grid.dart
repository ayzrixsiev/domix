import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// The eight photographed categories, four across and two down - a product shot on a grey panel
/// inside a white card, with its name under it.
///
/// **Which eight is not a list kept here**: it is every category [ProductCategory.photo] answers for,
/// in the enum's own order, so adding a shot to the assets and naming it on the enum is the whole of
/// promoting a category onto this grid. The categories without a photo are reached through search.
class PopularCategoriesGrid extends StatelessWidget {
  const PopularCategoriesGrid({super.key, required this.onCategoryTap});

  /// passed in rather than pushed from here, so this stays a pure renderer with no route knowledge
  final void Function(ProductCategory category) onCategoryTap;

  /// derived, never hand-written - see the class doc
  static List<ProductCategory> get photographed => ProductCategory.values
      .where((category) => category.photo != null)
      .toList();

  static const int _columns = 4;
  static const double _gap = 8;

  // the panel, its inset and the name row. a constant rather than a childAspectRatio, which derives
  // height from *width* - that made the cell grow on a wide phone and shrink on a narrow one until
  // a two-line name no longer fit.
  static const double _inset = 5;
  static const double _photoHeight = 56;
  static const double _labelHeight = 34;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final categories = photographed;

    return GridView.builder(
      // the feed is the scrollable here; a grid that also scrolled would fight it for the same drag
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisExtent: _inset + _photoHeight + _labelHeight,
        crossAxisSpacing: _gap,
        mainAxisSpacing: _gap,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryCard(
          // non-null by construction: `photographed` filtered on exactly this
          photo: category.photo!,
          label: category.label(strings),
          onTap: () => onCategoryTap(category),
        );
      },
    );
  }
}

/// One category: a grey panel holding the product shot, its name under it.
///
/// **No chevron on the card.** At four columns on a phone the card is about 84dp, and a name plus a
/// chevron on one line does not fit at any size worth reading. The only chevron is the section's own
/// "Все категории", where it points at something new rather than repeating what a tap already implies.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.photo,
    required this.label,
    required this.onTap,
  });

  final String photo;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // a bit more travel than the default: 3% on a card this small is barely perceptible
    return PressableScale(
      pressedScale: 0.95,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PopularCategoriesGrid._inset,
                PopularCategoriesGrid._inset,
                PopularCategoriesGrid._inset,
                0,
              ),
              // concentric with the card: md minus the inset, near enough to sm
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  height: PopularCategoriesGrid._photoHeight,
                  width: double.infinity,
                  child: ColoredBox(
                    color: AppColors.photoPanel,
                    child: Image.asset(
                      photo,
                      // **the shots are cut onto white, and multiplying by the panel colour turns
                      // that white into the panel** - no box around the product, and the soft shadow
                      // under it survives. contain, because the shot is 1.3:1 and the panel wider.
                      color: AppColors.photoPanel,
                      colorBlendMode: BlendMode.multiply,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
