import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/presentation/widgets/home_header.dart';
import 'package:frontend/features/home/presentation/widgets/section_header.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
import 'package:frontend/features/home/presentation/widgets/popular_shops_carousel.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/home/presentation/widgets/shops_nearby.dart';

/// the page gutter every block shares - the same 16 the header and search bar sit on, so section
/// headings line up with them down the left edge
const EdgeInsets _gutter = EdgeInsets.symmetric(horizontal: 16);

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
  });

  final bool showScaffold;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HomeHeader(),
          Expanded(
            // no horizontal padding here on purpose: each block applies the shared gutter itself,
            // which lets the carousel opt out and bleed to the screen edges while every heading
            // still lines up with the DOMIX pill and the search bar above it
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 14),
                  const Padding(padding: _gutter, child: SearchAndLikeBar()),

                  const SizedBox(height: 26),
                  Padding(
                    padding: _gutter,
                    child: SectionHeader(
                      title: strings.popularShops,
                      actionLabel: strings.viewAll,
                      onAction: () {},
                    ),
                  ),
                  const SizedBox(height: 12),
                  const PopularShopsCarousel(),

                  const SizedBox(height: 26),
                  Padding(
                    padding: _gutter,
                    child: SectionHeader(
                      title: strings.popularCategories,
                      actionLabel: strings.seeAll,
                      onAction: () {},
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(padding: _gutter, child: PopularCategoriesGrid()),

                  const SizedBox(height: 26),
                  Padding(
                    padding: _gutter,
                    child: SectionHeader(title: strings.shopsNearbyTitle),
                  ),
                  const SizedBox(height: 12),
                  const Padding(padding: _gutter, child: ShopsNearbyGrid()),

                  SizedBox(height: bottomPadding),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }
}
