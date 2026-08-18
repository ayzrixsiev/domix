import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/home/data/home_content.dart';

/// One shop as a full-width row: placeholder photo, name, rating, address, price comparison.
///
/// Lifted out of `best_offers.dart`, where it was a private `_BestOfferRow`, once the category
/// drill-down needed the identical thing. A shop should carry the same weight wherever it appears,
/// and two copies of a card is how one of them quietly grows a different shadow.
///
/// A vertical row rather than a grid cell, which is what this used to be: each cell had to fit a
/// name, a rating, a street and a price into half the screen's width, which forced all of it down
/// to 11px with nothing emphasised.
class HomeShopRow extends StatelessWidget {
  const HomeShopRow({super.key, required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.hairline),
          // matches the VIP cards: six of these stacked down the page is the section that most
          // needed separating from the background
          boxShadow: AppShadows.raised,
        ),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            // the same placeholder treatment the shop details sheet uses for a photoless shop, so a
            // shop looks like the same object wherever it appears in the app
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
                      // the star block only exists when there is something to put in it. with no
                      // reviews table every shop reads 0.0, and "⭐ 0.0" says the opposite of what
                      // is true - see Shop.hasRating. the address slides left into the space.
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
                  // the badge goes under the address rather than beside the price, because it is a
                  // sentence and the trailing column is a number - putting words where a figure is
                  // expected is what made the first attempt at this row unscannable
                  if (shop.priceTier case final tier?) ...[
                    const SizedBox(height: 5),
                    PriceTierBadge(
                      tier: tier,
                      differencePercent: shop.priceDifferencePercent,
                      strings: strings,
                      compact: true,
                    ),
                  ],
                ],
              ),
            ),
            // the basket total sits at the trailing edge, where it lines up down the column and can
            // be read shop against shop at a glance - the whole point of the number.
            //
            // omitted entirely when the shop has none, rather than shown as a zero. an owner who has
            // priced almost nothing has no basket, and printing 0 would make the emptiest shop look
            // like the cheapest.
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
    );
  }
}

/// A small caption over a bold figure, right-aligned at the row's trailing edge.
///
/// A separate widget rather than an inline Column because the entire value of putting a number at
/// the trailing edge is that the eye can run down it, which only holds while every row builds it
/// identically.
class _TrailingAmount extends StatelessWidget {
  const _TrailingAmount({required this.label, required this.amount});

  final String label;
  final String amount;

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
        const SizedBox(height: 2),
        Text(
          amount,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
