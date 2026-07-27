import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_placeholder_content.dart';
import 'section_header.dart';

// renamed from InfiniteShopCarousel: it was never infinite. it rendered the same four placeholder
// shops twice (`itemCount: shops.length * 2`) and attached a PageController to a ListView - a
// controller that does nothing there, was rebuilt on every frame, and was never disposed. a name
// that describes what the widget actually is beats one describing what it was meant to become.
class PopularShopsCarousel extends StatelessWidget {
  const PopularShopsCarousel({super.key});

  static const double _cardHeight = 148;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: strings.popularShops,
          actionLabel: strings.viewAll,
          onAction: () {},
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            // lets each card's shadow spill past the strip instead of being cropped at its edges
            clipBehavior: Clip.none,
            itemCount: kPopularShops.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _PopularShopCard(shop: kPopularShops[index], strings: strings),
          ),
        ),
      ],
    );
  }
}

// the one deliberately dark surface in the app. it gives the home page a single focal point, which
// is what makes the white cards around it read as calm rather than empty - the same reason a wallet
// app puts one dark card at the top. everything else stays light.
class _PopularShopCard extends StatelessWidget {
  const _PopularShopCard({required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  static const Color _onDark = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF23232F), Color(0xFF33334A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        // softened from 18% black at 14px blur: a dark card already separates itself from a light
        // page by value alone, so the shadow only needs to hint at lift
        boxShadow: const [
          BoxShadow(color: Color(0x1F1A1D2E), blurRadius: 18, offset: Offset(0, 8)),
        ],
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
                    color: _onDark,
                    fontSize: 17,
                    height: 1.2,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _onDark.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.star, color: AppColors.starYellow, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      shop.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: _onDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(LucideIcons.map_pin, color: _onDark.withValues(alpha: 0.4), size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shop.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _onDark.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          // same hairline-then-metric structure as the light cards elsewhere, just inverted. the
          // orange-filled, orange-bordered chip that used to sit here was the loudest element on
          // the entire home screen.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 1,
                child: ColoredBox(color: _onDark.withValues(alpha: 0.1)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    strings.averageCheckShort,
                    style: TextStyle(
                      color: _onDark.withValues(alpha: 0.45),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      strings.somAmount(shop.averagePaycheck),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _onDark,
                        fontSize: 12.5,
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
