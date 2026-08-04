import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/products/data/product_category.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';

/// Every priced product in one category, across every shop, cheapest first - what a "Популярные
/// категории" tile opens onto.
///
/// **Products, not shops.** The tile used to lead to a list of shops that stocked the category, and
/// answering "who sells сантехника" left the customer to open each shop and search it. The question
/// they tapped to ask is "what can I buy and for how much"; the shop's name rides on every tile, so
/// this answers both at once.
///
/// The same [ProductGrid] and [ProductTile] the owner's catalogue and the map's shop sheet use - one
/// grid, three audiences. A product should look like the same object wherever it appears, and three
/// copies of a product card is how one of them quietly grows a different shadow.
///
/// It owns its own loading and error state rather than putting them on [HomeController]: this is a
/// screen someone opens, reads and leaves, and a failure here must not paint an error over the home
/// screen behind it.
class CategoryProductsScreen extends StatefulWidget {
  const CategoryProductsScreen({super.key, required this.category});

  final ProductCategory category;

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  List<CategoryProduct>? _products;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final products = await context.read<HomeController>().productsForCategory(widget.category);
      // the request outlives the screen if the user backs out mid-flight, and setState on a
      // disposed State throws. `mounted` is the guard for exactly that, and it has to be checked
      // *after* every await, not once at the top.
      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.category.label(strings),
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              // the count once loaded, the generic subtitle before that - a number that appears out
              // of nowhere a beat after the screen opens reads as a glitch
              _products == null
                  ? strings.categoryProductsSubtitle
                  : strings.productsCountLabel(_products!.length),
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(top: false, child: _body(strings)),
    );
  }

  Widget _body(AppLocalizations strings) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    // every non-loading state sits under one RefreshIndicator, so a pull works whether the screen
    // is showing tiles, an error or an empty state. the two shrink-wrapping states go through
    // _FullPage to be scrollable at all - see its own comment for why that is not optional.
    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: _load,
      child: _content(strings),
    );
  }

  Widget _content(AppLocalizations strings) {
    if (_error != null) {
      return _FullPage(
        child: EmptyStateView(
          icon: CupertinoIcons.wifi_exclamationmark,
          // the same danger treatment my_shops_screen uses for a failed load: identical layout, but
          // a failure should not look like a friendly "nothing here yet"
          iconColor: AppColors.danger,
          iconBackground: AppColors.dangerSoft,
          title: strings.categoryProductsLoadError,
          subtitle: _error,
          action: PrimaryActionButton(label: strings.retryButtonShort, onTap: _load),
        ),
      );
    }

    final products = _products ?? const <CategoryProduct>[];
    if (products.isEmpty) {
      return _FullPage(
        // the category's own glyph, following the convention that arriving somewhere should feel
        // like arriving at the thing you tapped
        child: EmptyStateView(
          icon: widget.category.icon,
          title: strings.noProductsInCategory,
          subtitle: strings.noProductsInCategoryHint,
        ),
      );
    }

    return ProductGrid(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      tiles: [
        for (final entry in products)
          ProductTile(
            product: entry.product,
            strings: strings,
            // the shop is the whole reason this list is browsable: a price with no seller attached
            // answers a question nobody asked
            subtitle: entry.shopName,
          ),
      ],
    );
  }
}

/// A full-page empty/error state that still scrolls, so pull-to-refresh works on it.
///
/// This is the shape `ShopProductsScreen._FullPageState` documents: a `RefreshIndicator` builds a
/// Stack that gives its child *loose* constraints with `AlignmentDirectional.topStart`, so any
/// shrink-wrapping child renders jammed in the top-left corner - and since the indicator only
/// drives a scrollable, the pull gesture does nothing at all. `AlwaysScrollableScrollPhysics` is
/// the other half: content that fits exactly has nothing to overscroll, and without it the gesture
/// is never recognised.
class _FullPage extends StatelessWidget {
  const _FullPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
