import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/home/data/home_placeholder_content.dart';

/// A page-snapping carousel of VIP (paid placement) shops that loops endlessly in both directions.
///
/// **How the loop works.** `PageView.builder` with a null `itemCount` is unbounded *forwards* only:
/// the underlying `SliverChildBuilderDelegate` has no concept of a negative index, so there is no
/// built-in way to scroll backwards forever. The standard solution, and the one every carousel
/// package uses, is to start deep inside a very large virtual range instead: the item index is
/// mapped onto the real list with a modulo, so page 25 000 and page 25 005 both render shop 0.
/// Swiping forward never ends, and backwards there are [_loopOrigin] × shops pages to burn through
/// before index 0 is reachable - about twenty-five thousand swipes.
///
/// Two details make that safe rather than a trick:
///  * The starting page is an exact multiple of the shop count, so the carousel opens on the first
///    shop rather than an arbitrary one.
///  * Dart's `%` is Euclidean - `-1 % 5` is `4`, not `-1` - so the mapping stays correct even if an
///    index below the origin is ever built.
class VipShopsCarousel extends StatefulWidget {
  const VipShopsCarousel({super.key});

  /// Card + peek. The page is this fraction of the screen; the leftover is split between the two
  /// neighbours, so an edge of the previous and next shop is always visible and the strip reads as
  /// continuous rather than as a single card.
  static const double viewportFraction = 0.84;

  static const double cardHeight = 216;

  @override
  State<VipShopsCarousel> createState() => _VipShopsCarouselState();
}

class _VipShopsCarouselState extends State<VipShopsCarousel> {
  /// how many full cycles sit behind the opening page
  static const int _loopOrigin = 5000;

  late final PageController _controller;
  late final int _initialPage;

  @override
  void initState() {
    super.initState();
    _initialPage = _loopOrigin * kVipShops.length;
    _controller = PageController(
      viewportFraction: VipShopsCarousel.viewportFraction,
      initialPage: _initialPage,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The page the viewport is centred on, as a fraction. Reading `.page` before the first layout
  /// throws, so this falls back to the starting page until the controller is attached.
  double get _currentPage {
    if (_controller.hasClients && _controller.position.hasContentDimensions) {
      return _controller.page ?? _initialPage.toDouble();
    }
    return _initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;

    return SizedBox(
      height: VipShopsCarousel.cardHeight,
      child: PageView.builder(
        controller: _controller,
        // unbounded: the builder is asked for whatever page the user swipes to, forever
        itemCount: null,
        padEnds: true,
        itemBuilder: (context, index) {
          final shop = kVipShops[index % kVipShops.length];

          // rebuilds on every scroll tick so the off-centre cards can settle back slightly. it is
          // what makes the swipe feel like cards moving through a viewport rather than a filmstrip
          // sliding sideways.
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final distance = (_currentPage - index).abs().clamp(0.0, 1.0);
              return Transform.scale(
                scale: 1 - distance * 0.05,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _VipShopCard(shop: shop, strings: strings),
            ),
          );
        },
      ),
    );
  }
}

// these cards were a near-black gradient, which put the single darkest object in the app right at
// the top of its brightest screen. they are white now, with the shop's identity carried by a soft
// branded banner instead of by an inverted colour scheme - and that banner is where a real shop
// photo will go once photo upload exists, so the layout will not need rethinking then.
class _VipShopCard extends StatelessWidget {
  const _VipShopCard({required this.shop, required this.strings});

  final HomeShopPreview shop;
  final AppLocalizations strings;

  static const double _bannerHeight = 120;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
        // `raised`, not `card`: this is the section the eye should land on first, and it is the
        // one surface here big enough that a barely-there shadow just looks like a rendering
        // artefact rather than depth
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Banner(rating: shop.rating),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 16,
                          height: 1.2,
                          letterSpacing: -0.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.location_solid,
                            color: AppColors.textFaint,
                            size: 11,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              shop.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 12,
                                height: 1.3,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        strings.averageCheckShort,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
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
                            color: AppColors.textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md - 1)),
      child: Container(
        height: _VipShopCard._bannerHeight,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primarySoft, AppColors.surfaceMuted],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                CupertinoIcons.building_2_fill,
                color: AppColors.primaryOrange.withValues(alpha: 0.38),
                size: 34,
              ),
            ),
            // sits on the banner rather than beside the name: it is a badge about the shop as a
            // whole, and keeping it here leaves the name a full line to itself
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  boxShadow: AppShadows.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 11),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
