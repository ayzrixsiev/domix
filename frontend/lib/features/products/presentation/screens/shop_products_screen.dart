import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import '../../data/product_category.dart';
import '../../data/product_model.dart';
import '../../data/product_section.dart';
import '../controllers/products_controller.dart';
import '../widgets/product_grid.dart';
import '../widgets/product_section_bar.dart';
import '../widgets/product_tile.dart';
import 'product_edit_screen.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/pressable_scale.dart';

/// mirrors maxCustomProducts in backend/internal/endpoints/product_crud.go, which is what actually
/// enforces it - this copy only greys the add tile out before a doomed round trip
const int kMaxCustomProducts = 30;

// the "Товары" section of ShopSettingsScreen: the shop's whole catalogue as a grid, in the layout a
// customer sees on the shop's card. it arrives already full, because creating the shop copied its
// category's template in.
//
// two kinds of tile share the grid: template rows are the shared basket (only price and availability
// change), and the owner's own rows are fully theirs. only the second kind counts against the
// allowance on the last cell.
class ShopProductsScreen extends StatefulWidget {
  const ShopProductsScreen({super.key, required this.shop});

  final Shop shop;

  @override
  State<ShopProductsScreen> createState() => _ShopProductsScreenState();
}

class _ShopProductsScreenState extends State<ShopProductsScreen> {
  // null is «Все товары»
  ProductSection? _section;

  // an owner looking for one row of a hundred was scrolling for it
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // name and description, since the size lives in the description. not the unit: «шт» would match
  // most of the catalogue.
  List<Product> _matching(List<Product> products) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return products;
    return [
      for (final product in products)
        if ('${product.name} ${product.specs}'.toLowerCase().contains(query)) product,
    ];
  }

  @override
  void initState() {
    super.initState();
    // deferred past the first frame: loadProducts notifies before its first await, which from initState
    // trips flutter's "setState() called during build" guard. cached per shop, so revisiting does not
    // re-fetch.
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
          // a new product opens with the category of the last one in the list, which for a seeded shop is a
          // real category from its own template. only a starting point, but right more often than an empty
          // field is.
          suggestedCategory: product == null ? _lastCategory(controller) : null,
        ),
      ),
    );
  }

  ProductCategory? _lastCategory(ProductsController controller) {
    final products = controller.productsFor(widget.shop.id);
    if (products.isEmpty) return null;
    // tryFromCode, so a legacy free-text category simply does not preselect anything rather than being
    // carried forward into a new product
    return ProductCategory.tryFromCode(products.last.category);
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<ProductsController>(context);

    final shopId = widget.shop.id;
    final products = controller.productsFor(shopId);
    final isLoading = controller.isLoadingFor(shopId);
    final loadFailed = controller.loadFailedFor(shopId);

    return Scaffold(
      backgroundColor: AppColors.background,
      // no magnifier opposite the title: the search is a field on the page now, and a header that
      // also opened one would be the same control offered twice
      appBar: AppPageHeader(
        title: strings.productsScreenTitle,
        subtitle: strings.productsScreenSubtitle,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              color: AppColors.primaryOrange,
              // the catalogue is the one thing a second device could have changed, so pull-to-refresh
              // forces past the session cache
              onRefresh: () => controller.loadProducts(shopId, force: true),
              child: _body(context, strings, controller, products, isLoading, loadFailed),
            ),
            // not while the first load or its failure is the whole screen: there is nothing to add to
            if (!(products.isEmpty && (isLoading || loadFailed)))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _AddProductBar(
                  strings: strings,
                  used: controller.customCountFor(shopId),
                  max: kMaxCustomProducts,
                  onTap: () => _openEditor(),
                ),
              ),
          ],
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
    bool loadFailed,
  ) {
    // a spinner only on the very first load: once there are tiles, a refresh happens underneath them
    if (isLoading && products.isEmpty) {
      return const _FullPageState(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    if (loadFailed && products.isEmpty) {
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
    final (priced, total) = controller.templatePricingProgressFor(widget.shop.id);

    final sections = sectionsOf(products);
    final section = sections.contains(_section) ? _section : null;
    final shown = productsBySection(_matching(products), only: section);

    // **A CustomScrollView, and the grid below is a sliver rather than a shrink-wrapped GridView.** A
    // shrink-wrapped grid lays out every child to measure itself, so all 100 tiles mount at once and
    // each Image.network fires immediately - and the symptom was not slow images but a **failed price
    // save**, the PUT queueing behind them until its own timeout. See ProductSliverGrid.
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CatalogueSummary(
                  shop: widget.shop,
                  strings: strings,
                  priced: priced,
                  total: total,
                ),
                const SizedBox(height: 20),

                if (products.isEmpty) ...[
                  _CenteredMessage(
                    icon: CupertinoIcons.cube_box,
                    title: strings.noProductsInShop,
                    subtitle: strings.noProductsInShopHint,
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ),

        // not while the catalogue is empty: a field over nothing, and a sheet with no sections in it
        if (products.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            sliver: SliverToBoxAdapter(
              child: CatalogueSearchBar(
                controller: _search,
                products: products,
                selected: section,
                onSelected: (value) => setState(() => _section = value),
                strings: strings,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: ProductSliverGrid(
            tiles: [
              for (final product in shown)
                ProductTile(
                  product: product,
                  strings: strings,
                  showOwnBadge: true,
                  onTap: () => _openEditor(product: product),
                ),
            ],
          ),
        ),

        if (shown.isEmpty && products.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Text(
                strings.searchNoResults,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),

        SliverPadding(
          // clears the floating add button: its height, its two margins and the gradient above it
          padding: const EdgeInsets.fromLTRB(20, 14, 20, _AddProductBar.clearance),
          sliver: SliverToBoxAdapter(
            child: customCount >= kMaxCustomProducts
                ? Text(
                    strings.ownProductsLimitReachedHint(kMaxCustomProducts),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// "Добавить товар" pinned at the bottom of the screen, where the thumb is, instead of the last cell
// of a hundred-tile grid. the fade behind it lets tiles slide under without a hard edge. spent
// allowance greys it out and says so on the button itself, rather than after a wasted tap.
class _AddProductBar extends StatelessWidget {
  const _AddProductBar({
    required this.strings,
    required this.used,
    required this.max,
    required this.onTap,
  });

  final AppLocalizations strings;
  final int used;
  final int max;
  final VoidCallback onTap;

  static const double _buttonHeight = 56;
  static const double _fade = 28;
  static const double _bottomMargin = 14;

  /// what the end of the scroll has to leave free so the last row is not under the button
  static const double clearance = _fade + _buttonHeight + _bottomMargin + 14;

  bool get _isFull => used >= max;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.background.withValues(alpha: 0), AppColors.background],
          stops: const [0, 0.4],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, _fade, 20, _bottomMargin),
        child: PressableScale(
          onTap: _isFull ? null : onTap,
          child: Container(
            height: _buttonHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _isFull ? AppColors.trackGrey : AppColors.primaryOrange,
              borderRadius: BorderRadius.circular(999),
              boxShadow: _isFull ? null : AppShadows.accent(AppColors.primaryOrange),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isFull) ...[
                  const Icon(LucideIcons.plus, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                ],
                Text(
                  _isFull ? strings.ownProductsUsedLabel(used, max) : strings.addProductButton,
                  style: TextStyle(
                    color: _isFull ? AppColors.textGrey : Colors.white,
                    fontSize: 16.5,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w700,
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

// a single centred message occupying the whole viewport - the spinner and the load error both go
// through it. RefreshIndicator gives its child loose constraints at `topStart`, so anything that
// shrink-wraps lands in the corner, and it only drives a *scrollable*, so pull-to-refresh did
// nothing in the error state. a scroll view forced to at least viewport height fixes both.
class _FullPageState extends StatelessWidget {
  const _FullPageState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder to learn the viewport height, since a scroll view's child is unbounded and cannot
    // ask for "as tall as the screen" on its own
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // AlwaysScrollable, or a child that fits exactly has nothing to overscroll and the pull gesture is
        // never recognised - which is precisely the error state
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

// the header strip: which template stocked this shop and how far through pricing it the owner is.
// the bar is a threshold rather than a tally - at 99 of 99 the shop enters the price comparison, at
// 98 it is not in it at all - which is why it counts basket rows only.
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(LucideIcons.store, color: AppColors.primaryOrange, size: 26),
              ),
              const SizedBox(width: 14),
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
                        fontSize: 17,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w800,
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
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: AppColors.success,
                  size: 20,
                ),
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

          // hidden only for a shop with no template at all, which no real shop has - a "0 left" line under an
          // empty bar would be a promise about a catalogue that is not there
          if (total > 0) ...[
            const SizedBox(height: 10),
            Text(
              isComplete
                  ? strings.priceIndexParticipating
                  : strings.priceIndexNeedsEveryPrice(total - priced),
              style: TextStyle(
                color: isComplete ? AppColors.success : AppColors.textGrey,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// the same nested-layer empty state the tickets tab, notifications and my-shops list use
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
