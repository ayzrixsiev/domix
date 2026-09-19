import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';

/// One fetch of cross-shop products and the four states it can be in. Everything below a screen's
/// app bar - [ProductResultsScreen] puts a title above it, [ProductSearchScreen] a text field.
///
/// **Re-running it means giving it a new [Key]**: it loads once from `initState` and holds the
/// result, so a new key builds a fresh State instead of racing a second request.
class ProductResultsView extends StatefulWidget {
  const ProductResultsView({
    super.key,
    required this.strings,
    required this.load,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    this.query = '',
    this.canSearchWider = false,
    this.onCountChanged,
  });

  final AppLocalizations strings;

  final Future<List<CategoryProduct>> Function() load;

  /// differs between the callers: "nobody has priced anything in this category yet" and "that search
  /// matched nothing" are different facts and deserve different sentences
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  /// Narrows what is already loaded, live as it is typed. **A client-side filter over the fetched
  /// list, not a second request**: the category is already in memory, and re-querying the api on
  /// every keystroke is the thing [ProductSearchScreen] deliberately does not do either.
  ///
  /// Empty on the search screen, which has nothing to narrow - its list *is* the query's answer.
  final String query;

  /// Whether this screen can go wider than what it loaded - a category page can search the whole
  /// catalogue, the search screen already has. Only changes what the empty state offers.
  final bool canSearchWider;

  /// fires with the count **that is on screen**, so a filter that hides nine of ten rows is reflected
  /// in the app bar rather than leaving it claiming ten. null on a failure - "0 товаров" and "the
  /// request failed" are not the same sentence, and only one of them is true.
  final void Function(int? count)? onCountChanged;

  @override
  State<ProductResultsView> createState() => _ProductResultsViewState();
}

class _ProductResultsViewState extends State<ProductResultsView> {
  List<CategoryProduct>? _products;
  bool _isLoading = true;

  /// what kind of failure, never the exception's text - it picks one of three written sentences
  LoadFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // typing does not refetch; it re-filters what is already here. the count in the app bar has to
  // follow, and it is reported after the frame rather than inside didUpdateWidget - the parent is
  // mid-build at that point and calling its setState there is the "setState during build" crash.
  @override
  void didUpdateWidget(ProductResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query == oldWidget.query || _products == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCountChanged?.call(_visible().length);
    });
  }

  /// The loaded products the current [ProductResultsView.query] leaves standing.
  ///
  /// **Every word has to appear somewhere**, matching how the server's search reads a query, so
  /// "клей эрон" finds the row that "эрон клей" finds. The shop name is searched too: on a
  /// cross-shop list, narrowing to one seller is the other thing a filter is for.
  List<CategoryProduct> _visible() {
    final products = _products ?? const <CategoryProduct>[];
    final query = widget.query.trim().toLowerCase();
    if (query.isEmpty) return products;

    final words = query.split(RegExp(r'\s+'));
    return [
      for (final entry in products)
        if (words.every(
          (word) => '${entry.product.name} ${entry.shopName}'.toLowerCase().contains(word),
        ))
          entry,
    ];
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _failure = null;
    });

    try {
      final products = await widget.load();
      // the request outlives the widget if the user backs out mid-flight, and `mounted` has to be
      // checked *after* every await, not once at the top
      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoading = false;
      });
      widget.onCountChanged?.call(_visible().length);
    } catch (e) {
      if (!mounted) return;
      debugPrint('ProductResultsView: could not load results: $e');
      setState(() {
        _failure = LoadFailure.of(e);
        _isLoading = false;
      });
      widget.onCountChanged?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    // every non-loading state sits under one RefreshIndicator. the two shrink-wrapping ones go through
    // _FullPage to be scrollable at all - see its own comment for why that is not optional.
    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: _load,
      child: _content(),
    );
  }

  Widget _content() {
    final strings = widget.strings;

    if (_failure case final failure?) {
      return _FullPage(
        child: EmptyStateView(
          // the wifi glyph only when the connection is the problem
          icon: failure == LoadFailure.network
              ? CupertinoIcons.wifi_exclamationmark
              : CupertinoIcons.exclamationmark_circle,
          // danger-coloured: a failure should not look like a friendly "nothing here yet"
          iconColor: AppColors.danger,
          iconBackground: AppColors.dangerSoft,
          title: strings.categoryProductsLoadError,
          subtitle: strings.loadErrorHintFor(failure),
          action: PrimaryActionButton(label: strings.retryButtonShort, onTap: _load),
        ),
      );
    }

    final products = _visible();
    if (products.isEmpty) {
      // **two different empty states, because they are two different facts.** "nobody has priced
      // anything in this category" is about the market; "your filter matched none of the 100 rows
      // that are here" is about the four letters just typed, and offering the first for the second
      // tells the user the category is bare when it is not.
      final filtered = widget.query.trim().isNotEmpty;
      return _FullPage(
        child: EmptyStateView(
          icon: filtered ? CupertinoIcons.search : widget.emptyIcon,
          title: filtered ? strings.categoryFilterNoResults : widget.emptyTitle,
          // the "press search to look everywhere" line is only true where there is a wider search
          subtitle: filtered && widget.canSearchWider
              ? strings.categoryFilterNoResultsHint
              : (filtered ? strings.searchNoResultsHint : widget.emptyHint),
        ),
      );
    }

    return ProductGrid(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      // dragging the results puts the keyboard away; a no-op on the category screen, where none is open
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      tiles: [
        for (final entry in products)
          ProductTile(
            product: entry.product,
            strings: strings,
            // a price with no seller attached answers a question nobody asked
            subtitle: entry.shopName,
            // this is the browse surface, so the shopper's two controls belong here
            showBuyerActions: true,
            // the tile carries only shop_id, so this is the one route into a shop card that fetches
            onTap: () => openShopById(context, entry.product.shopId),
          ),
      ],
    );
  }
}

/// A full-page empty/error state that still scrolls, so pull-to-refresh works on it: a
/// `RefreshIndicator` gives its child loose constraints at `topStart` and only drives a scrollable,
/// so a shrink-wrapping child lands in the corner and the pull does nothing.
class _FullPage extends StatelessWidget {
  const _FullPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
