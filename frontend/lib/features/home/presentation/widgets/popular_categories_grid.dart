import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// The eight photographed categories, four across and two down - a product shot on a white card
/// with its name under it.
///
/// **Which eight is not a list kept here.** It is every category [ProductCategory.photo] answers
/// for, in the enum's own order, so adding a shot to the assets and naming it on the enum is the
/// whole of promoting a category onto this grid - there is no second list to forget.
///
/// **The pager and its dots are gone, and so is "Все категории".** The four categories without a
/// photo are not on the home screen; they are still reached through search.
class PopularCategoriesGrid extends StatelessWidget {
  const PopularCategoriesGrid({super.key, required this.onCategoryTap});

  /// passed in rather than pushed from here, so this stays a pure renderer with no route knowledge
  final void Function(ProductCategory category) onCategoryTap;

  /// derived, never hand-written - see the class doc
  static List<ProductCategory> get photographed =>
      ProductCategory.values.where((category) => category.photo != null).toList();

  static const int _columns = 4;
  static const double _gap = 8;

  // the photo slot plus the name strip below it. a constant rather than a childAspectRatio, which
  // derives height from *width* - that made the cell grow on a wide phone and shrink on a narrow
  // one until a two-line name no longer fit.
  static const double _photoHeight = 64;
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
        mainAxisExtent: _photoHeight + _labelHeight,
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

/// One category: the product shot filling the top of a white card, its name under it.
///
/// **No chevron on the card.** The reference this is built from has one per tile, but that layout
/// is a wide one - at four columns on a phone the card is about 86dp, and a name plus a chevron on
/// one line does not fit at any size worth reading. The only chevron is the section's own "Все
/// категории", where it points at something new rather than repeating what a tap already implies.
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
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: AppShadows.card,
        ),
        // the card's own radius, so the photo is cut by the corner instead of squaring it off
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Column(
            children: [
              // full-bleed rather than inset inside the card: an inset would spend 8dp of an 86dp
              // card on margin, and it has nothing to show there - the ground is the same white.
              SizedBox(
                height: PopularCategoriesGrid._photoHeight,
                width: double.infinity,
                // the shots are cut onto a pure white ground, so the whole card is one white
                // surface and the frame before an image decodes is the colour of the frame after it.
                //
                // **they arrived on a light grey ground and it could not stay.** The reference this
                // is built from insets a grey panel inside a white card, which works on a white
                // page; ours is #EFF1F5, and grey-on-grey left the top two thirds of every card
                // with no edge at all - only the name strip read as a card.
                child: ColoredBox(
                  color: AppColors.surfaceWhite,
                  child: Image.asset(
                    photo,
                    // the assets are 1.3:1 and the slot is a little wider on most phones, so cover
                    // trims a few pixels top and bottom - the product sits in the middle 80% of
                    // every file for exactly that reason
                    fit: BoxFit.cover,
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
      ),
    );
  }
}
