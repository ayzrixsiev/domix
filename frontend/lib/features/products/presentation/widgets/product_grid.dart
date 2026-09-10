import 'package:flutter/material.dart';
import 'product_tile.dart';

// the two-per-row product layout, shared by the owner's management screen and the customer-facing
// catalogue - the point is that an owner sees their shop exactly as a customer will. [tiles] is
// built widgets rather than products, so the owner's grid can slot AddProductTile in as the last
// cell rather than below the grid.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.tiles,
    this.padding = EdgeInsets.zero,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> tiles;

  final EdgeInsets padding;

  /// `onDrag` on the search results, `manual` everywhere else, since nowhere else has a keyboard open
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  static const double spacing = 12;

  /// Shared by [ProductGrid] and [ProductSliverGrid] so the two lay out identically. A fixed row
  /// height rather than childAspectRatio - see the comment on [ProductTile.height].
  static const SliverGridDelegate gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    mainAxisExtent: ProductTile.height,
  );

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: keyboardDismissBehavior,
      itemCount: tiles.length,
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

/// The same grid as a **sliver**, for a screen with other content above it.
///
/// **`shrinkWrap: true` is not a layout convenience, it is a network decision**: a shrink-wrapped
/// grid lays out every child to measure itself, so a 100-product catalogue mounts 100 tiles and
/// fires 100 image requests - and the symptom is a **failed price save**, not slow images.
///
/// **Reach for this whenever the grid is not the only thing on the page.**
class ProductSliverGrid extends StatelessWidget {
  const ProductSliverGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      itemCount: tiles.length,
      gridDelegate: ProductGrid.gridDelegate,
      itemBuilder: (context, index) => tiles[index],
    );
  }
}
