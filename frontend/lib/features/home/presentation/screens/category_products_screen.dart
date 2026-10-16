import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/product_results_screen.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Every priced product in one category, across every shop - what a "Популярные категории" tile
/// opens onto. **Products, not shops**: the shop's name rides on every tile, so it answers both.
///
/// The screen itself is [ProductResultsScreen], shared with search; this class only supplies the
/// heading, glyph and empty-state wording.
class CategoryProductsScreen extends StatelessWidget {
  const CategoryProductsScreen({super.key, required this.category});

  final ProductCategory category;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    // resolved here, not inside the callback: `load` runs on pull-to-refresh long after this build,
    // and reading a provider off a deactivated element throws
    final home = context.read<HomeController>();

    return ProductResultsScreen(
      title: category.label(strings),
      subtitle: strings.categoryProductsSubtitle,
      load: () => home.productsForCategory(category),
      // the field in the app bar can leave this category behind - see ProductResultsScreen.onSearch
      onSearch: (query, offset) => home.searchProducts(query, offset: offset),
      // the category's own glyph: arriving somewhere should feel like arriving at the thing you tapped
      emptyIcon: category.icon,
      emptyTitle: strings.noProductsInCategory,
      emptyHint: strings.noProductsInCategoryHint,
    );
  }
}
