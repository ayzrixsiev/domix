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
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> tiles;

  /// true when the grid is nested inside another scroll view (the shop details sheet). it then
  /// measures all its children up front and scrolls with the parent instead of on its own - two
  /// scrollables sharing one gesture is how a list ends up refusing to move.
  final bool shrinkWrap;

  final EdgeInsets padding;

  /// Whether dragging the grid puts the phone's keyboard away. `onDrag` on the search results,
  /// `manual` (Flutter's default) everywhere else, since nowhere else has a keyboard open behind it.
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  static const double spacing = 12;

  /// Shared by [ProductGrid] and [ProductSliverGrid] so the two lay out identically. A fixed row
  /// height rather than childAspectRatio - see the comment on [ProductTile.height] for why.
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
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
      keyboardDismissBehavior: keyboardDismissBehavior,
      itemCount: tiles.length,
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

/// The same grid as a **sliver**, for a screen that has other content above it.
///
/// **This exists because `shrinkWrap: true` is not a layout convenience, it is a network
/// decision.** A shrink-wrapped grid has to measure its own height, and the only way to do that is
/// to lay out every child - so a 100-product catalogue mounts 100 [ProductTile]s at once, and each
/// one's `Image.network` fires a request the moment it mounts. Down an ngrok tunnel that is 100
/// requests and several megabytes before anything else on the connection gets a turn, and the
/// symptom is not slow images: it is that **saving a price fails**, because the PUT queues behind
/// the backlog and trips its own 10-second timeout without ever leaving the phone. It comes back on
/// its own once the images finish, which is exactly the shape of bug nobody believes is real.
///
/// A sliver in a [CustomScrollView] builds only what is on screen, so a catalogue of any size costs
/// one screenful of requests. Reach for this whenever the grid is not the only thing on the page;
/// `shrinkWrap` stays for the shop sheet, which cannot become a CustomScrollView as cheaply.
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
