import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/home/data/home_content.dart';

/// One shop as a full-width row. A row rather than a grid cell: half the screen's width forced the
/// name, rating, street and price all down to 11px with nothing emphasised.
class HomeShopRow extends StatelessWidget {
  const HomeShopRow({
    super.key,
    required this.shop,
    required this.strings,
    this.onTap,
  });

  final HomeShopPreview shop;
  final AppLocalizations strings;

  /// nullable only so a caller with nowhere to navigate can leave it out; every home row has one
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline),
            // **No shadow.** `raised` and then `card` were both tried: on the #EFF1F5 page a black
            // shadow at any alpha is a grey shape around the row, and fifteen of them stacked down
            // the section read as a column of grey boxes. White against #EFF1F5 with a hairline is
            // already a clear edge - there is nothing for a shadow to add here.
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              // the same placeholder the shop card uses for a photoless shop, so a shop looks like the same
              // object wherever it appears
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primarySoft, AppColors.surfaceMuted],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  CupertinoIcons.building_2_fill,
                  color: AppColors.primaryOrange.withValues(alpha: 0.45),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14.5,
                        height: 1.25,
                        letterSpacing: -0.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // the star block only exists when there is something to put in it: with no reviews table every
                        // shop reads 0.0, and "⭐ 0.0" says the opposite of what is true. the address slides left.
                        if (shop.hasRating) ...[
                          const Icon(
                            CupertinoIcons.star_fill,
                            color: AppColors.starYellow,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            shop.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            shop.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 11.5,
                              height: 1.3,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // under the address rather than beside the price: it is a sentence and the trailing column is a
                    // number, and words where a figure is expected is what made this row unscannable
                    if (shop.priceTier case final tier?) ...[
                      const SizedBox(height: 5),
                      PriceTierBadge(
                        tier: tier,
                        differencePercent: shop.priceDifferencePercent,
                        strings: strings,
                        size: PriceTierBadgeSize.compact,
                      ),
                    ],
                  ],
                ),
              ),
              // the basket total sits at the trailing edge, where it lines up down the column and can be read
              // shop against shop at a glance. omitted entirely when there is none rather than shown as a zero,
              // which would make the emptiest shop look like the cheapest.
              if (shop.basketPrice case final basket?) ...[
                const SizedBox(width: 10),
                _TrailingAmount(
                  label: strings.basketPriceShort,
                  amount: strings.somAmount(basket),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An open place in a category's ranking: [HomeShopRow]'s layout with field names where its values
/// would be. What an owner reads off thirteen open rows is "finishing my prices puts me in it".
///
/// **No invented shop anywhere in it** - no name, street, price or percentage; the rating is the one
/// exception, a fixed 5 ([kSlotRating]). **Drawn at full strength, not faded**: washed-out frames
/// under one real shop read as a section that failed to load.
class EmptyShopRow extends StatelessWidget {
  const EmptyShopRow({super.key, required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      // the same surface a real row wears: an open place is a thing being advertised, and fifteen faded
      // frames under one real shop made the section look broken rather than available. the text is what
      // says "open".
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          // the same peach placeholder tile a real row draws, so the two line up down the column
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primarySoft, AppColors.surfaceMuted],
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              CupertinoIcons.building_2_fill,
              color: AppColors.primaryOrange.withValues(alpha: 0.45),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.slotShopNameLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 14.5,
                    height: 1.25,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    // drawn in full, unlike a real row where the star waits for reviews: here the star *is* part of
                    // what is being described
                    const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 11),
                    const SizedBox(width: 3),
                    const Text(
                      kSlotRating,
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.slotAddressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  strings.slotComparisonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11,
                    height: 1.2,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // the caption stays and the figure goes, so the number's column still lines up down the section
          _TrailingAmount(label: strings.slotBasketLabel, amount: null),
        ],
      ),
    );
  }
}

/// A small caption over a bold figure, right-aligned at the row's trailing edge. Its own widget
/// because the value of a number at the trailing edge is that the eye can run down it, which only
/// holds while every row builds it identically.
class _TrailingAmount extends StatelessWidget {
  const _TrailingAmount({required this.label, required this.amount});

  final String label;

  /// Null on an open place, which draws the caption alone. Not an empty string: `Text('')` still
  /// takes a line box, so equal heights would be an accident rather than a construction.
  final String? amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
          ),
        ),
        if (amount case final value?) ...[
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }
}
