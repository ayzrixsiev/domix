import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
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
/// result, so a `ValueKey(query)` builds a fresh State instead of racing a second request.
class ProductResultsView extends StatefulWidget {
  const ProductResultsView({
    super.key,
    required this.strings,
    required this.load,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    this.onCountChanged,
  });

  final AppLocalizations strings;

  final Future<List<CategoryProduct>> Function() load;

  /// differs between the callers: "nobody has priced anything in this category yet" and "that search
  /// matched nothing" are different facts and deserve different sentences
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  /// fires with the result count so an app bar above can show one. null on a failure - "0 товаров"
  /// and "the request failed" are not the same sentence, and only one of them is true.
  final void Function(int? count)? onCountChanged;

  @override
  State<ProductResultsView> createState() => _ProductResultsViewState();
}

class _ProductResultsViewState extends State<ProductResultsView> {
  List<CategoryProduct>? _products;
  bool _isLoading = true;

  /// **a flag, not the exception's text**: one written sentence and a retry; the exception is logged
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _failed = false;
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
      widget.onCountChanged?.call(products.length);
    } catch (e) {
      if (!mounted) return;
      debugPrint('ProductResultsView: could not load results: $e');
      setState(() {
        _failed = true;
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

    if (_failed) {
      return _FullPage(
        child: EmptyStateView(
          icon: CupertinoIcons.wifi_exclamationmark,
          // danger-coloured: a failure should not look like a friendly "nothing here yet"
          iconColor: AppColors.danger,
          iconBackground: AppColors.dangerSoft,
          title: strings.categoryProductsLoadError,
          subtitle: strings.loadErrorHint,
          action: PrimaryActionButton(label: strings.retryButtonShort, onTap: _load),
        ),
      );
    }

    final products = _products ?? const <CategoryProduct>[];
    if (products.isEmpty) {
      return _FullPage(
        child: EmptyStateView(
          icon: widget.emptyIcon,
          title: widget.emptyTitle,
          subtitle: widget.emptyHint,
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
