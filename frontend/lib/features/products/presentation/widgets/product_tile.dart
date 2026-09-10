import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import '../../data/product_model.dart';

// one product as a square card in a two-per-row grid. a fixed height (see [height]) rather than an
// aspect ratio, which derives height from *width* - so the same tile grows on a wide phone and the
// text block underneath, which needs the same room everywhere, is what breaks first.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.strings,
    this.onTap,
    this.showOwnBadge = false,
    this.subtitle,
  });

  final Product product;
  final AppLocalizations strings;

  /// A second line under the name - the selling shop, on the cross-shop browse, where it is the
  /// difference between a price and an actionable price. When present the product name is capped to
  /// one line, so the tile keeps its fixed [height].
  final String? subtitle;

  /// null on the customer-facing grid: a tile that lights up under a finger but does nothing when
  /// released reads as broken
  final VoidCallback? onTap;

  /// only the owner's own grid distinguishes their products from the template's
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
      // the ink splash of a tapped tile must not paint over the card's rounded corners, and the banner
      // has to be clipped to them too
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
                    maxLines: subtitle == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 12.5,
                      height: 1.28,
                      letterSpacing: -0.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle case final shop?) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(CupertinoIcons.building_2_fill,
                            color: AppColors.textFaint, size: 10),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            shop,
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
                    ),
                  ],
                  // pushes the price to the bottom edge, so prices line up across a row whether a name wrapped onto
                  // one line or two
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

// the photo, or the placeholder that stands in for one.
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
          // always painted, and always *under* the photo rather than instead of it: it is what shows while
          // the image downloads and what is left if it fails, so the tile never flashes a bare white rectangle
          const _BannerPlaceholder(),
          // **the thumbnail, not the photo.** a shop card is up to a hundred tiles, and at 1000px apiece that
          // is ~15 MB down a mobile connection for a band 118px tall. `thumbUrl` already falls back to the
          // full-size url when the backend did not send one.
          if (product.thumbUrl case final url?)
            _BannerPhoto(url: url, fallbackUrl: product.imageUrl),

          // in stock is the normal case and the one nobody needs told, so only the two exceptions get a chip
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

// **Plain white, and that is about the photos rather than the empty state.** This is painted *under*
// every tile and the photo on top is `contain`, so it is the bars either side of the picture. A
// peach-to-grey gradient made a shot cut out on white read as pasted onto the tile; white is the
// white the photos are flattened onto, so the seam disappears. The cost - a photoless product is a
// white band with one glyph - is the right way round, since that is the exception.
class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceWhite,
      child: Center(
        child: Icon(CupertinoIcons.cube_box_fill, color: AppColors.textFaint, size: 30),
      ),
    );
  }
}

// the product photo. `contain`, not `cover`: these are catalogue shots of a single object on white,
// and cropping one to a 118px band cuts the head off a hammer.
//
// [cacheWidth] is the one line that keeps a 99-tile grid from running out of memory - without it a
// 1000x1000 jpeg costs 4 MB of raw bitmap however small it is drawn. [fallbackUrl] covers exactly
// one failure: a missing thumbnail, generated by a `magick` command somebody runs by hand.
class _BannerPhoto extends StatelessWidget {
  const _BannerPhoto({required this.url, this.fallbackUrl});

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
          : _BannerPhoto(url: fallbackUrl!),
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

// a solid white pill rather than a translucent one: it sits over a gradient, and a tint that reads
// correctly against the light end washes out against the dark end
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
