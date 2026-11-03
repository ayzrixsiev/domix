import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import '../../data/product_model.dart';

/// One product as a card in a two-per-row grid: photo, name, the description line under it, price.
/// A fixed height (see [height]) rather than an aspect ratio, so a wide phone does not grow the
/// photo and squeeze the text.
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

  /// the selling shop, under the price - only on the cross-shop grids, where it is what makes the
  /// price actionable
  final String? subtitle;

  /// null on the customer-facing grid: a tile that lights up under a finger but does nothing reads
  /// as broken
  final VoidCallback? onTap;

  /// only the owner's own grid distinguishes their products from the template's
  final bool showOwnBadge;

  /// the heart - off on the owner's grid, they are not shopping in their own catalogue
  final bool showBuyerActions;

  final bool isFavorite;

  /// null leaves the heart drawn but inert, which is what a preview wants
  final VoidCallback? onFavoriteToggle;

  /// frame 6 + panel 100 + text 122: two lines of name, two of description, the price, the shop
  /// line. every text carries an explicit line height, so this holds on any font.
  static const double height = 230;

  static const double _photoHeight = 100;

  /// the white margin between the card's edge and the photo panel, on three sides
  static const double _frame = 6;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13.5,
                      height: 1.25,
                      letterSpacing: -0.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // two lines of its own, never squeezed out by a long name: the size lives here
                  if (product.specs.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.specs,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  // pushes the price to the bottom edge, so prices line up across a row
                  const Spacer(),
                  _PriceLine(product: product, strings: strings),
                  if (subtitle case final shop?) ...[
                    const SizedBox(height: 4),
                    _ShopLine(name: shop),
                  ],
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

/// The grey panel the photo is mounted on, with the availability badge and the heart over it.
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
              // **the catalogue photos are shot on this exact colour** - see AppColors.photoPanel
              color: AppColors.photoPanel,
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
            child: _AvailabilityBadge(
              availability: product.availability,
              strings: strings,
            ),
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
              child: _TileChip(
                label: strings.ownProductBadge,
                color: AppColors.primaryOrange,
              ),
            ),
        ],
      ),
    );
  }
}

// what shows while the photo downloads, and what is left if it fails
class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        CupertinoIcons.cube_box_fill,
        color: AppColors.textFaint,
        size: 30,
      ),
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
      ProductAvailability.inStock => (
        AppColors.success,
        strings.availabilityBadgeInStock,
      ),
      ProductAvailability.onOrder => (
        AppColors.warning,
        strings.availabilityBadgeOnOrder,
      ),
      ProductAvailability.unavailable => (
        AppColors.textGrey,
        strings.availabilityBadgeUnavailable,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The heart over the photo panel.
///
/// A white disc with a `trackGrey` ring, so it still reads over a light photo.
///
/// The disc stays white when saved and only the glyph fills: a red disc at 26px reads as a warning
/// badge on a product tile, where a red heart reads as saved.
class _FavouriteButton extends StatelessWidget {
  const _FavouriteButton({
    required this.label,
    required this.saved,
    this.onTap,
  });

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
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
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
          fontSize: 12,
          height: 1.5,
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
              fontSize: 15.5,
              height: 1.2,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w800,
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
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
