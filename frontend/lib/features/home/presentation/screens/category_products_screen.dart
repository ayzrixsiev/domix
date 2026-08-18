import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/product_results_screen.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// Every priced product in one category, across every shop, cheapest first - what a "Популярные
/// категории" tile opens onto.
///
/// **Products, not shops.** The tile used to lead to a list of shops that stocked the category, and
/// answering "who sells сантехника" left the customer to open each shop and search it. The question
/// they tapped to ask is "what can I buy and for how much"; the shop's name rides on every tile, so
/// this answers both at once.
///
/// The screen itself is [ProductResultsScreen], shared with the home screen's search results - both
/// are a list of products from across the market and both need the same three states handled the
/// same way. This class is what supplies the category's own heading, glyph and empty-state wording;
/// it stays a separate type rather than a call site because a category tile navigating to a
/// half-configured generic screen would put this configuration in the widget that pushes it.
class CategoryProductsScreen extends StatelessWidget {
  const CategoryProductsScreen({super.key, required this.category});

  final ProductCategory category;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    // resolved here rather than inside the callback. `load` runs on pull-to-refresh, potentially
    // long after this build, and reading a provider off a context whose element has been deactivated
    // throws - holding the controller itself sidesteps the question entirely.
    final home = context.read<HomeController>();

    return ProductResultsScreen(
      title: category.label(strings),
      subtitle: strings.categoryProductsSubtitle,
      load: () => home.productsForCategory(category),
      // the category's own glyph, following the convention that arriving somewhere should feel like
      // arriving at the thing you tapped
      emptyIcon: category.icon,
      emptyTitle: strings.noProductsInCategory,
      emptyHint: strings.noProductsInCategoryHint,
    );
  }
}
