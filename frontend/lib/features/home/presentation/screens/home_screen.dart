import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/presentation/widgets/home_header.dart';
import 'package:frontend/features/home/presentation/widgets/section_header.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/home/presentation/widgets/vip_shops_carousel.dart';

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

                  // none of the three section headings carries a "see all" action any more. each
                  // section already shows everything it has: the VIP carousel loops endlessly in
                  // both directions, the categories grid pages through all twelve, and Лучшие
                  // предложения is a top-N that has no longer tail to open. a link promising more
                  // than the section holds would have to lead somewhere, and there is nowhere.
                  const SizedBox(height: 26),
                  Padding(
                    padding: _gutter,
                    child: SectionHeader(title: strings.vipShops),
                  ),
                  const SizedBox(height: 12),
                  const VipShopsCarousel(),

                  const SizedBox(height: 26),
                  Padding(
                    padding: _gutter,
                    child: _SectionPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SectionHeader(title: strings.popularCategories),
                          const SizedBox(height: 14),
                          const PopularCategoriesGrid(),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),
                  Padding(
                    padding: _gutter,
                    child: SectionHeader(title: strings.bestOffersTitle),
                  ),
                  const SizedBox(height: 12),
                  const Padding(padding: _gutter, child: BestOffersList()),

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

// The white panel behind the categories grid.
//
// The home feed is otherwise deliberately container-free - an earlier pass wrapped every section
// in a panel and it was removed, so this is not a return to that. Only the categories grid gets
// one, because it is the one section made of small tinted tiles rather than self-contained cards:
// without a surface behind them the eight tiles read as loose objects scattered on the page rather
// than as one group, which is exactly what the box is there to fix.
//
// It sits on `_gutter` like everything else, so its border lines up down the left edge with the
// DOMIX pill, the search bar and every section heading - the alignment is the point; an inset or
// full-bleed panel here would break the column the whole feed is built on.
class _SectionPanel extends StatelessWidget {
  const _SectionPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // less padding at the bottom than the top on purpose: the only thing that ever sits at the
      // bottom edge of this panel is the categories pager's dot row, which already carries its own
      // touch padding. matching the 14 above it counted that space twice and left the panel looking
      // stretched below its content.
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}
