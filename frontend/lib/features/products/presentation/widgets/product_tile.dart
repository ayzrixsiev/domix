import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import '../../data/product_model.dart';

// one product, as a square card in a two-per-row grid - the layout every marketplace uses for a
// catalogue, and the one a shop owner will recognise without being taught it.
//
// the card is a fixed height (see [height]) rather than a fixed aspect ratio. aspect ratio derives
// height from width, so the same tile grows on a wide phone and shrinks on a narrow one, and the
// text block underneath - which needs the same room everywhere - is what breaks first. this is the
// same reason PopularCategoriesGrid sizes with mainAxisExtent.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.strings,
    this.onTap,
    this.showOwnBadge = false,
  });

  final Product product;
  final AppLocalizations strings;

  /// null on the customer-facing grid: a shop's card is for looking, and a tile that lights up
  /// under a finger but does nothing when released reads as broken
  final VoidCallback? onTap;

  /// only the owner's own grid distinguishes their products from the template's - to a customer
  /// the distinction means nothing
  final bool showOwnBadge;

  /// banner 118 + text block 90. hand-tuned to fit a two-line name plus a price row at the smallest
  /// width the app supports, with nothing left over at the largest.
  static const double height = 208;
  static const double _bannerHeight = 118;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      // the ink splash of a tapped tile must not paint over the card's rounded corners, and the
      // banner has to be clipped to them too
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductBanner(
            product: product,
            strings: strings,
            showOwnBadge: showOwnBadge,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
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
                  // pushes the price to the bottom edge, so prices line up across a row no matter
                  // whether a name wrapped onto one line or two
                  const Spacer(),
                  _PriceLine(product: product, strings: strings),
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

// products have no photos yet, exactly like shops don't (see ShopBanner in map_screen.dart), so
// this is the same idea: a near-neutral surface with the faintest warm tint, not a saturated block
// of brand colour. a placeholder should not be the loudest thing on the card.
class _ProductBanner extends StatelessWidget {
  const _ProductBanner({
    required this.product,
    required this.strings,
    required this.showOwnBadge,
  });

  final Product product;
  final AppLocalizations strings;
  final bool showOwnBadge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ProductTile._bannerHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primarySoft, AppColors.surfaceMuted],
              ),
            ),
          ),
          Center(
            child: Icon(
              CupertinoIcons.cube_box_fill,
              color: AppColors.primaryOrange.withValues(alpha: 0.34),
              size: 30,
            ),
          ),

          // in stock is the normal case and the one nobody needs told, so only the two exceptions
          // get a chip - otherwise every tile in the grid would carry the same green label
          if (product.availability != ProductAvailability.inStock)
            Positioned(
              top: 8,
              left: 8,
              child: _TileChip(
                label: product.availability == ProductAvailability.onOrder
                    ? strings.availabilityOnOrder
                    : strings.availabilityUnavailable,
                color: product.availability == ProductAvailability.onOrder
                    ? AppColors.starYellow
                    : AppColors.textGrey,
              ),
            ),

          if (showOwnBadge && !product.isTemplate)
            Positioned(
              top: 8,
              right: 8,
              child: _TileChip(label: strings.ownProductBadge, color: AppColors.primaryOrange),
            ),
        ],
      ),
    );
  }
}

// a solid white pill rather than a translucent one: it sits over a gradient, and a tint that reads
// correctly against the light end of it washes out against the dark end
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

// price, or the prompt that replaces it. a freshly created shop has this prompt on every single
// tile - it is the owner's to-do list - which is why it is the one place on the card allowed to
// use brand orange: it is an action to take, not information.
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

// the last cell of the owner's grid: a slot shaped like a product card but obviously empty, so
// "add one of your own" sits where the eye already is instead of on a button somewhere else.
// disabled once the allowance is spent, with the reason on the tile rather than in a snackbar the
// owner would only see after a wasted round trip.
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
