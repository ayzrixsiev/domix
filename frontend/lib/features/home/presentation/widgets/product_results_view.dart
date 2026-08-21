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

/// One fetch of cross-shop products and the four states it can be in: loading, failed, empty, and a
/// grid. Everything below a screen's app bar, and nothing above it.
///
/// **It is a widget rather than a screen because two screens need exactly this and nothing else.**
/// `ProductResultsScreen` (a category tile's drill-down) wraps it in a titled app bar;
/// `ProductSearchScreen` puts a text field up there instead and swaps this in as soon as there is a
/// query worth running. Both ask the customer's question a different way - "what плитка is there"
/// and "who sells цемент" - and get the same kind of answer back, so duplicating the three states
/// would be three chances for the two to start behaving differently.
///
/// **Re-running it means giving it a new [Key].** It loads once, from `initState`, and holds the
/// result - there is deliberately no "change the query on the existing state" path, because a
/// second in-flight request would have to be raced against the first. A `ValueKey(query)` makes
/// Flutter throw this State away and build a fresh one, which is the same thing without the race.
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

  /// The empty state, which differs between the callers: "nobody has priced anything in this
  /// category yet" and "that search matched nothing" are different facts and deserve different
  /// sentences. The glyph follows the convention that arriving somewhere should feel like arriving
  /// at the thing you tapped.
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  /// Fires with the number of results once a load lands, so an app bar above can show a count it
  /// has no other way of knowing. Null on a failure - "0 товаров" and "the request failed" are not
  /// the same sentence, and only one of them is true.
  final void Function(int? count)? onCountChanged;

  @override
  State<ProductResultsView> createState() => _ProductResultsViewState();
}

class _ProductResultsViewState extends State<ProductResultsView> {
  List<CategoryProduct>? _products;
  bool _isLoading = true;

  /// **A flag, not the exception's text.** The failure gets one written sentence and a retry; the
  /// exception goes to the log. See the same note on `ShopByIdScreen._gone`.
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
      // the request outlives the widget if the user backs out mid-flight, and setState on a disposed
      // State throws. `mounted` is the guard for exactly that, and it has to be checked *after*
      // every await, not once at the top.
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

    // every non-loading state sits under one RefreshIndicator, so a pull works whether the screen
    // is showing tiles, an error or an empty state. the two shrink-wrapping states go through
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
          // the same danger treatment my_shops_screen uses for a failed load: identical layout, but
          // a failure should not look like a friendly "nothing here yet"
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
      // dragging the results puts the keyboard away, which is the gesture people already make when
      // a phone keyboard is covering what they wanted to read. it does nothing on the category
      // screen, where no keyboard was ever open.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      tiles: [
        for (final entry in products)
          ProductTile(
            product: entry.product,
            strings: strings,
            // the shop is the whole reason this list is browsable: a price with no seller attached
            // answers a question nobody asked
            subtitle: entry.shopName,
            // and the name has to be reachable, or the list ends in a dead end. the tile carries
            // only shop_id, so this is the one route into a shop card that fetches - see
            // ShopByIdScreen.
            onTap: () => openShopById(context, entry.product.shopId),
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
