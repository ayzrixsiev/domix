import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/features/home/presentation/widgets/home_header.dart';
import 'package:frontend/features/home/presentation/widgets/popular_shops_carousel.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/home/presentation/widgets/shops_nearby.dart';

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
    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HomeHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const SearchAndLikeBar(),
                  const SizedBox(height: 24),
                  const PopularShopsCarousel(),
                  const SizedBox(height: 24),
                  const PopularCategoriesGrid(),
                  const SizedBox(height: 24),
                  const ShopsNearbyGrid(),
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
