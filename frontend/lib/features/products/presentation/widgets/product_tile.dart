import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import '../../data/product_model.dart';

/// One product as a card in a two-per-row grid. A fixed height (see [height]) rather than an aspect
/// ratio, which derives height from *width* - so the same tile grows on a wide phone and the text
/// block underneath, which needs the same room everywhere, is what breaks first.
///
/// **The card is grey and the photo panel inside it is white** - the inverse of the obvious way
/// round, and it is load-bearing rather than decorative. Every catalogue shot is a product
/// photographed on white, so a *grey* panel showed that white as a rectangle around each product.
/// Putting the white on the panel lets the photo's own background disappear into it, and moves the
/// grey out to the card, where nothing is composited against it.
///
/// It also means the 410 committed catalogue JPEGs need no reprocessing at all: the alternative was
/// repainting every one of their backgrounds to match a panel colour, which would have welded the
/// assets to a hex value in this file.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.strings,
    this.onTap,
    this.showOwnBadge = false,
    this.showBuyerActions = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.subtitle,
  });

  final Product product;
  final AppLocalizations strings;

  /// A line under the price - the selling shop, on the cross-shop browse, where it is the difference
  /// between a price and an actionable price.
  final String? subtitle;

  /// null on the customer-facing grid: a tile that lights up under a finger but does nothing when
  /// released reads as broken
  final VoidCallback? onTap;

  /// only the owner's own grid distinguishes their products from the template's
  final bool showOwnBadge;

  /// The heart and the basket button. **Off on the owner's management grid** - they are not shopping
  /// in their own catalogue. The basket stays inert: it is phase two.
  final bool showBuyerActions;

  /// Whether the heart is filled.
  final bool isFavorite;

  /// Saves or unsaves. Null leaves the heart drawn but inert, which is what a preview wants.
  final VoidCallback? onFavoriteToggle;

  /// Photo block 124 (the panel's 118 plus the 6 of frame above it) + text block 98. Hand-tuned to
  /// fit a two-line name, a price, the shop line and the basket button at the smallest width the app
  /// supports, with nothing left over at the largest.
  static const double height = 222;

  /// the grey panel's own height. [_frame] of white sits above it and either side.
  static const double _photoHeight = 118;

  /// the white margin between the card's edge and the photo panel, on three sides
  static const double _frame = 6;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      // trackGrey rather than the `cardGrey` that was on the panel: #F1F3F6 is *lighter* than the
      // #EFF1F5 page, so a card filled with it is two units from its background and disappears.
      //
      // **No border.** One was tried in `textFaint`, since every lighter neutral is at or above this
      // fill and would ring a grey card in a paler line. It was visible and it was worse: twelve
      // outlined boxes down a scrolling grid read as a table. The fill carries the shape on its own.
      decoration: BoxDecoration(
        color: AppColors.trackGrey,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      // the ink splash of a tapped tile must not paint over the card's rounded corners
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // no bottom inset: the panel's lower edge meets the text block, so the white frame reads as
          // a margin around the picture rather than as a box drawn around it
          Padding(
            padding: const EdgeInsets.fromLTRB(_frame, _frame, _frame, 0),
            child: _PhotoPanel(
              product: product,
              strings: strings,
              showOwnBadge: showOwnBadge,
              showFavourite: showBuyerActions,
              isFavorite: isFavorite,
              onFavoriteToggle: onFavoriteToggle,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 12.5,
                      height: 1.28,
                      letterSpacing: -0.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // pushes the price to the bottom edge, so prices line up across a row whether a name
                  // wrapped onto one line or two
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PriceLine(product: product, strings: strings),
                            if (subtitle case final shop?) ...[
                              const SizedBox(height: 4),
                              _ShopLine(name: shop),
                            ],
                          ],
                        ),
                      ),
                      if (showBuyerActions) ...[
                        const SizedBox(width: 6),
                        _BasketButton(label: strings.addToBasketLabel),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: card,
      ),
    );
  }
}

/// The white panel the photo is mounted on, with the availability badge and the heart over it.
class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({
    required this.product,
    required this.strings,
    required this.showOwnBadge,
    required this.showFavourite,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  final Product product;
  final AppLocalizations strings;
  final bool showOwnBadge;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final bool showFavourite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ProductTile._photoHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // the panel, and the only thing here that clips: the photo has to take its rounded corners,
          // while the badges sit on top of them
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ColoredBox(
              // white, and the whole point of the layout - see the class doc on [ProductTile]
              color: AppColors.surfaceWhite,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // always painted, and always *under* the photo rather than instead of it: it is what
                  // shows while the image downloads and what is left if it fails
                  const _PanelPlaceholder(),
                  // **the thumbnail, not the photo.** a shop card is up to a hundred tiles, and at
                  // 1000px apiece that is ~15 MB down a mobile connection for a panel 118px tall.
                  // `thumbUrl` already falls back to the full-size url when the backend sent none.
                  if (product.thumbUrl case final url?)
                    _PanelPhoto(url: url, fallbackUrl: product.imageUrl),
                ],
              ),
            ),
          ),
          Positioned(
            top: 7,
            left: 7,
            child: _AvailabilityBadge(availability: product.availability, strings: strings),
          ),
          if (showFavourite)
            Positioned(
              top: 7,
              right: 7,
              child: _FavouriteButton(
                label: strings.addToFavouritesLabel,
                saved: isFavorite,
                onTap: onFavoriteToggle,
              ),
            ),
          // the owner's marker moves to the bottom: the top right is the shopper's heart, and on the
          // owner's own grid the heart is off, but the two must not be able to collide either way
          if (showOwnBadge && !product.isTemplate)
            Positioned(
              bottom: 7,
              right: 7,
              child: _TileChip(label: strings.ownProductBadge, color: AppColors.primaryOrange),
            ),
        ],
      ),
    );
  }
}

// **The panel is white and the photo sits straight on it.** The catalogue shots are `contain`, so
// whatever is behind them is the bars either side of the picture - and since every one of those
// shots was taken on white, white is the one colour that leaves no seam.
class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(CupertinoIcons.cube_box_fill, color: AppColors.textFaint, size: 30),
    );
  }
}

// the product photo. `contain`, not `cover`: these are catalogue shots of a single object, and
// cropping one to a 118px band cuts the head off a hammer.
//
// [cacheWidth] is the one line that keeps a 99-tile grid from running out of memory - without it a
// 1000x1000 jpeg costs 4 MB of raw bitmap however small it is drawn. [fallbackUrl] covers exactly
// one failure: a missing thumbnail, generated by a `magick` command somebody runs by hand.
class _PanelPhoto extends StatelessWidget {
  const _PanelPhoto({required this.url, this.fallbackUrl});

  final String url;
  final String? fallbackUrl;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      cacheWidth: 540,
      // an unreachable server or a photo nobody has added yet leaves the placeholder showing rather than
      // flutter's broken-image glyph. a missing *thumbnail* is different: the full-size photo is right
      // there, so try it once - the nested widget passes no fallback, which stops this recursing.
      errorBuilder: (_, _, _) => fallbackUrl == null || fallbackUrl == url
          ? const SizedBox.shrink()
          : _PanelPhoto(url: fallbackUrl!),
      // fades in once decoded instead of popping, and shows nothing before then - the placeholder
      // underneath is already the loading state
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: AppMotion.base,
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}

/// All three availability states, as a solid pill. **Every tile carries one**, where the old card
/// showed a chip only for the two exceptions: on a marketplace "в наличии" is the fact a shopper is
/// scanning for, and a card that says nothing when the answer is yes makes them check each one.
class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.availability, required this.strings});

  final ProductAvailability availability;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (availability) {
      ProductAvailability.inStock => (AppColors.success, strings.availabilityBadgeInStock),
      ProductAvailability.onOrder => (AppColors.warning, strings.availabilityBadgeOnOrder),
      ProductAvailability.unavailable =>
        (AppColors.textGrey, strings.availabilityBadgeUnavailable),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.xs)),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The heart over the photo panel.
///
/// A ringed white disc, not a plain one: the panel behind it is white too, so without the
/// `trackGrey` edge there is no disc at all - just a heart floating on the photo.
///
/// The disc stays white when saved and only the glyph fills: a red disc at 26px reads as a warning
/// badge on a product tile, where a red heart reads as saved.
class _FavouriteButton extends StatelessWidget {
  const _FavouriteButton({required this.label, required this.saved, this.onTap});

  final String label;
  final bool saved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: saved,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        // the disc is 26px, which is under the 44px a finger is aimed with - the padding is the
        // difference between a control and a decoration
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.trackGrey),
          ),
          // a matched Cupertino pair rather than one outline glyph recoloured: "saved" has to be
          // readable at 14px without comparing it to a tile that is not
          child: Icon(
            saved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: saved ? AppColors.danger : AppColors.textDark,
            size: 14,
          ),
        ),
      ),
    );
  }
}

/// The dark disc beside the price. **Inert**: the basket is phase two.
class _BasketButton extends StatelessWidget {
  const _BasketButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: AppColors.primaryDark, shape: BoxShape.circle),
        child: const Icon(LucideIcons.shopping_cart, color: Colors.white, size: 15),
      ),
    );
  }
}

/// Who is selling it. Under the price rather than under the name: the price and the shop are one
/// fact together, and splitting them put the name's second line between them.
class _ShopLine extends StatelessWidget {
  const _ShopLine({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.store, color: AppColors.textFaint, size: 10),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// a solid white pill rather than a translucent one: it sits over a photo, and a tint that reads
// correctly against a light shot washes out against a dark one
class _TileChip extends StatelessWidget {
  const _TileChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// price, or the prompt that replaces it. a freshly created shop has this prompt on every tile - the
// owner's to-do list - which is why it is the one place on the card allowed brand orange: it is an
// action to take, not information.
class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.product, required this.strings});

  final Product product;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    if (!product.hasPrice) {
      return Text(
        strings.priceNotSet,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.primaryOrange,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            strings.somAmount(product.price!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 14,
              letterSpacing: -0.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '/ ${product.unit}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// the last cell of the owner's grid: a slot shaped like a product card but obviously empty, so "add
// one of your own" sits where the eye already is. disabled once the allowance is spent, with the
// reason on the tile rather than in a snackbar seen after a wasted round trip.
class AddProductTile extends StatelessWidget {
  const AddProductTile({
    super.key,
    required this.strings,
    required this.used,
    required this.max,
    required this.onTap,
  });

  final AppLocalizations strings;
  final int used;
  final int max;
  final VoidCallback onTap;

  bool get _isFull => used >= max;

  @override
  Widget build(BuildContext context) {
    final accent = _isFull ? AppColors.textFaint : AppColors.primaryOrange;

    return Material(
      color: _isFull ? AppColors.surfaceMuted : AppColors.primarySoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: _isFull ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: _isFull ? AppColors.surfaceMuted : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.add, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 11),
                Text(
                  strings.addProductButton,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 12.5,
                    height: 1.28,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.ownProductsUsedLabel(used, max),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 10.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
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
