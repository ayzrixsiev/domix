import 'package:flutter/material.dart';
import 'product_tile.dart';

// the two-per-row product layout, shared by the owner's management screen and the customer-facing
// catalogue on a shop's card. one widget rather than two grids with the same delegate, because the
// whole point is that an owner sees their shop laid out exactly as a customer will.
//
// [tiles] is a list of built widgets rather than a list of products so the owner's grid can slot
// its AddProductTile in as the last cell - it lives in the flow of the grid, not below it.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.tiles,
    this.shrinkWrap = false,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> tiles;

  /// true when the grid is nested inside another scroll view (the shop details sheet). it then
  /// measures all its children up front and scrolls with the parent instead of on its own - two
  /// scrollables sharing one gesture is how a list ends up refusing to move.
  final bool shrinkWrap;

  final EdgeInsets padding;

  static const double spacing = 12;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        // a fixed row height, not childAspectRatio - see the comment on ProductTile.height for why
        mainAxisExtent: ProductTile.height,
      ),
      itemBuilder: (context, index) => tiles[index],
    );
  }
}
