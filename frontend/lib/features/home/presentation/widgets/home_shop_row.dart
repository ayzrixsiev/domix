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
  const HomeShopRow({
    super.key,
    required this.shop,
    required this.strings,
    this.onTap,
  });

  final HomeShopPreview shop;
  final AppLocalizations strings;

  /// Opens the shop card. Nullable only so a caller that has nowhere to navigate to - a widget test,
  /// or a future read-only surface - can leave it out; every row on the home screen has one.
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
            // matches the VIP cards: six of these stacked down the page is the section that most
            // needed separating from the background
            boxShadow: AppShadows.raised,
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              // the same placeholder treatment the shop card uses for a photoless shop, so a shop
              // looks like the same object wherever it appears in the app
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
                        size: PriceTierBadgeSize.compact,
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
      ),
    );
  }
}

/// An open place in a category's ranking: [HomeShopRow]'s layout with the field names where its
/// values would be.
///
/// **Same idea as the carousel's empty card and a different audience.** There the empty slot is
/// inventory being sold; here it is the ranking having room in it. What an owner reads off a tab with
/// two shops and thirteen open rows is "this category is not full, and finishing my prices puts me in
/// it" - which is the one message that reaches somebody stuck halfway through their catalogue, in the
/// place they are most likely to see it.
///
/// **No invented shop anywhere in it**: no name, no street, no price, no percentage. The rating is
/// the single exception and it is a fixed 5 ([kSlotRating]), describing the row rather than claiming
/// anything.
///
/// **Drawn at full strength, not faded.** A recessed treatment was tried - page-coloured fill, a
/// `trackGrey` outline, no shadow - and rejected for the same reason the carousel's was: a tab is
/// mostly open places at launch, and fifteen washed-out frames under one real shop read as a section
/// that failed to load rather than as one with room in it. The surface is identical to
/// [HomeShopRow]'s and the *words* are what differ.
///
/// The cost, accepted: a real row and an open one are alike at a glance, so what tells them apart is
/// reading «Название магазина». Built to the same height either way, so the section does not change
/// height as shops qualify.
class EmptyShopRow extends StatelessWidget {
  const EmptyShopRow({super.key, required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      // **the same surface a real row wears**, for the reason the carousel's empty card wears one:
      // an open place is a thing being advertised, and fifteen faded frames under one real shop made
      // the section look broken rather than look available. What says "open" is the text.
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.raised,
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
                    // drawn in full, unlike on a real row where the star is hidden until there are
                    // reviews (Shop.hasRating). here the star *is* part of what is being described.
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
          // the trailing column keeps its caption and loses its figure, so the number's column still
          // lines up down the section and the eye is not thrown by rows of different widths
          _TrailingAmount(label: strings.slotBasketLabel, amount: null),
        ],
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

  /// Null on an open place, which draws the caption alone. Not an empty string: `Text('')` still
  /// takes a line box, so the two rows would be the same height by accident rather than by
  /// construction, and a stray space in a translation would break it.
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
