import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_placeholder_content.dart';

// "Лучшие предложения" - the cheapest shops in the catalogue, cheapest first.
//
// This was "Магазины рядом с вами", a distance-ordered list. The ranking is now purely by average
// check across every shop, with no location input, so the row no longer shows a distance: keeping
// "0.5 км" next to a list that ignores location would have implied a proximity guarantee the
// section does not make. `kBestOffers` does the ranking (see home_placeholder_content.dart).
//
// A vertical list of cards, where this used to be a two-column grid: each grid cell had to carry a
// name, a rating, a street and an average check inside half the screen's width, which forced all of
// it down to 11px with nothing emphasised. Full-width rows give the shop name a line of its own.
class BestOffersList extends StatelessWidget {
  const BestOffersList({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Column(
      children: [
        for (var i = 0; i < kBestOffers.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _BestOfferRow(shop: kBestOffers[i], strings: strings),
        ],
      ],
    );
  }
}

class _BestOfferRow extends StatelessWidget {
  const _BestOfferRow({required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {},
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline),
            // matches the popular-shops cards: a shop should carry the same weight wherever it
            // appears, and six of these stacked down the page is the section that most needed
            // separating from the background
            boxShadow: AppShadows.raised,
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              // the same placeholder treatment the shop details sheet uses for a photoless shop,
              // so a shop looks like the same object wherever it appears in the app
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
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // the average check moves to the trailing edge, where it lines up down the column and
              // can be compared shop to shop at a glance - the whole point of the number
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.averageCheckShort,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    strings.somAmount(shop.averagePaycheck),
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
