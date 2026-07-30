import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import '../../data/product_category.dart';
import '../../data/product_model.dart';
import '../controllers/products_controller.dart';
import '../widgets/product_grid.dart';
import '../widgets/product_tile.dart';
import 'product_edit_screen.dart';

/// how many products of their own an owner may add on top of the category template. mirrors
/// maxCustomProducts in backend/internal/endpoints/product_crud.go, which is the one that actually
/// enforces it - this copy only greys the add tile out before a doomed round trip.
const int kMaxCustomProducts = 20;

// the "Товары" section of ShopSettingsScreen: the shop's whole catalogue as a grid, in exactly the
// layout a customer sees it on the shop's card. tap any tile to edit it, tap the last cell to add
// one of your own.
//
// the grid arrives already full, because creating the shop copied its category's template in. that
// is the design: an owner's first job is filling in prices on products that are already there, not
// typing a catalogue from nothing - which is what the excel upload existed to avoid, and why that
// upload has been removed rather than kept alongside this.
//
// two kinds of tile live in the same grid. the template rows are the shared basket: tappable, but
// only their price and availability can change. the owner's own rows, up to kMaxCustomProducts of
// them, are fully theirs. only the second kind counts against the allowance shown on the last cell.
class ShopProductsScreen extends StatefulWidget {
  const ShopProductsScreen({super.key, required this.shop});

  final Shop shop;

  @override
  State<ShopProductsScreen> createState() => _ShopProductsScreenState();
}

class _ShopProductsScreenState extends State<ShopProductsScreen> {
  @override
  void initState() {
    super.initState();
    // deferred to after the first frame: loadProducts calls notifyListeners() before its first
    // await, and calling that synchronously from initState - while the tree is still building -
    // trips flutter's "setState() called during build" guard. same reason MapScreen defers its own
    // load. cached per shop, so revisiting this screen doesn't re-fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductsController>().loadProducts(widget.shop.id);
    });
  }

  Future<void> _openEditor({Product? product}) {
    final controller = context.read<ProductsController>();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductEditScreen(
          shopId: widget.shop.id,
          product: product,
          // a new product opens with the category of the last one in the list, which for a seeded
          // shop is a real category from its own template. it is only a starting point - the
          // dropdown is right there - but it is right more often than an empty field is.
          suggestedCategory: product == null ? _lastCategory(controller) : null,
        ),
      ),
    );
  }

  ProductCategory? _lastCategory(ProductsController controller) {
    final products = controller.productsFor(widget.shop.id);
    if (products.isEmpty) return null;
    // tryFromCode, so a legacy free-text category simply doesn't preselect anything rather than
    // being carried forward into a new product
    return ProductCategory.tryFromCode(products.last.category);
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<ProductsController>(context);

    final shopId = widget.shop.id;
    final products = controller.productsFor(shopId);
    final isLoading = controller.isLoadingFor(shopId);
    final loadError = controller.loadErrorFor(shopId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        iconTheme: const IconThemeData(color: AppColors.textDark, size: 22),
        title: Text(
          strings.productsScreenTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryOrange,
          // the catalogue is the one thing on this screen a second device could have changed, so
          // pull-to-refresh forces past the session cache rather than reading it back
          onRefresh: () => controller.loadProducts(shopId, force: true),
          child: _body(context, strings, controller, products, isLoading, loadError),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations strings,
    ProductsController controller,
    List<Product> products,
    bool isLoading,
    String? loadError,
  ) {
    // a spinner only on the very first load. once there are tiles to show, a refresh happens
    // underneath them rather than replacing the screen with nothing.
    if (isLoading && products.isEmpty) {
      return const _FullPageState(
        child: CircularProgressIndicator(color: AppColors.primaryOrange),
      );
    }

    if (loadError != null && products.isEmpty) {
      return _FullPageState(
        child: _CenteredMessage(
          icon: CupertinoIcons.exclamationmark_circle,
          title: strings.productsLoadError,
          subtitle: strings.productsLoadErrorHint,
          actionLabel: strings.retryButtonShort,
          onAction: () => controller.loadProducts(widget.shop.id, force: true),
        ),
      );
    }

    final customCount = controller.customCountFor(widget.shop.id);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        _CatalogueSummary(
          shop: widget.shop,
          strings: strings,
          priced: controller.pricedCountFor(widget.shop.id),
          total: products.length,
        ),
        const SizedBox(height: 18),

        if (products.isEmpty) ...[
          _CenteredMessage(
            icon: CupertinoIcons.cube_box,
            title: strings.noProductsInShop,
            subtitle: strings.noProductsInShopHint,
          ),
          const SizedBox(height: 18),
        ],

        ProductGrid(
          // shrink-wrapped because it sits inside this ListView: two scrollables competing for one
          // drag gesture is how a grid ends up refusing to move
          shrinkWrap: true,
          tiles: [
            for (final product in products)
              ProductTile(
                product: product,
                strings: strings,
                showOwnBadge: true,
                onTap: () => _openEditor(product: product),
              ),
            // last cell, in the flow of the grid rather than on a button below it - "add one of
            // your own" belongs where the eye already is
            AddProductTile(
              strings: strings,
              used: customCount,
              max: kMaxCustomProducts,
              onTap: () => _openEditor(),
            ),
          ],
        ),

        if (customCount >= kMaxCustomProducts) ...[
          const SizedBox(height: 14),
          Text(
            strings.ownProductsLimitReachedHint(kMaxCustomProducts),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

// A single centred message occupying the whole viewport - the loading spinner and the load-error
// state both go through this.
//
// It exists because of two bugs that share one cause. RefreshIndicator builds a Stack whose child
// gets *loose* constraints and `AlignmentDirectional.topStart`, so anything that shrink-wraps -
// which _CenteredMessage does, being a Column with mainAxisSize.min - was laid out in the top-left
// corner instead of the middle of the screen. (The spinner escaped it only by accident: Center
// expands to fill a bounded box, so it happened to look right.)
//
// The second bug is the one that mattered more: RefreshIndicator only drives a *scrollable* child,
// so in the error state pull-to-refresh silently did nothing - on the one screen where retrying is
// the entire point. Making the state a scroll view that is forced to at least viewport height fixes
// both properly: the content is genuinely centred, and the gesture works everywhere the screen can
// appear rather than only when it happens to have content.
class _FullPageState extends StatelessWidget {
  const _FullPageState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder to learn the viewport height, since a scroll view's child is unbounded and
    // therefore cannot ask for "as tall as the screen" on its own
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // AlwaysScrollable, or a child that fits exactly has nothing to overscroll and the pull
        // gesture is never recognised - which is precisely the error state
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

// the header strip: which template stocked this shop, and how far through pricing it the owner is.
// the progress line is the point of the screen - a freshly created shop has 50 products and 0
// prices, and that number going up is the whole task.
class _CatalogueSummary extends StatelessWidget {
  const _CatalogueSummary({
    required this.shop,
    required this.strings,
    required this.priced,
    required this.total,
  });

  final Shop shop;
  final AppLocalizations strings;
  final int priced;
  final int total;

  @override
  Widget build(BuildContext context) {
    // guarded against total == 0: a shop with no products at all would otherwise divide by zero
    final progress = total == 0 ? 0.0 : priced / total;
    final isComplete = total > 0 && priced == total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: const Icon(CupertinoIcons.cube_box_fill, color: AppColors.primaryOrange, size: 18),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.category.label(strings),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        letterSpacing: -0.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.pricedProgressLabel(priced, total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isComplete) ...[
                const SizedBox(width: 10),
                const Icon(CupertinoIcons.checkmark_circle_fill, color: AppColors.success, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: AppColors.surfaceMuted,
              // green once finished: the bar stops being a to-do list and becomes a confirmation
              color: isComplete ? AppColors.success : AppColors.primaryOrange,
            ),
          ),
        ],
      ),
    );
  }
}

// the same nested-layer empty state the tickets tab, notifications and my-shops list use, rather
// than a fourth invention
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.textFaint, size: 27),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 15.5,
              letterSpacing: -0.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 7),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            Material(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: AppColors.primaryOrange,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
