import 'package:flutter/material.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/features/home/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:frontend/features/home/presentation/widgets/home_header.dart';
import 'package:frontend/features/home/presentation/widgets/infinite_shop_carousel.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/home/presentation/widgets/shops_nearby.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      bottomNavigationBar: const FloatingBottomNavBar(),
      body: SafeArea(
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
                  children: const [
                    SizedBox(height: 20),
                    SearchAndLikeBar(),
                    SizedBox(height: 18),
                    InfiniteShopCarousel(),
                    SizedBox(height: 16),
                    PopularCategoriesGrid(),
                    SizedBox(height: 16),
                    ShopsNearbyGrid(),
                    SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
