import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_placeholder_content.dart';
import 'section_header.dart';

class ShopsNearbyGrid extends StatelessWidget {
  const ShopsNearbyGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: strings.shopsNearbyTitle),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.12,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: kNearbyShops.length,
          itemBuilder: (context, index) =>
              _NearbyShopCard(shop: kNearbyShops[index], strings: strings),
        ),
      ],
    );
  }
}

class _NearbyShopCard extends StatelessWidget {
  const _NearbyShopCard({required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  shop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14.5,
                    height: 1.25,
                    letterSpacing: -0.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // rating sits inline with the name rather than in its own filled pill - it is one
              // number, and a background makes it compete with the shop's actual identity
              Row(
                children: [
                  const Icon(LucideIcons.star, color: AppColors.starYellow, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    shop.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              const Icon(LucideIcons.navigation, color: AppColors.textFaint, size: 11),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${shop.distanceKm} ${strings.nearbyDistanceAway} • ${shop.address}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          // a hairline plus quiet text, where a full-width filled grey block used to sit. the
          // average check is the same kind of secondary metric as on the my-shops card, so it gets
          // the same treatment rather than its own container.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    strings.averageCheckShort,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      strings.somAmount(shop.averagePaycheck),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
