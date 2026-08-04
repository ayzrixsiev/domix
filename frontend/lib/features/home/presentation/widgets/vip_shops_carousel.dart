import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/home/data/home_content.dart';

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
  const VipShopsCarousel({super.key, required this.shops});

  /// The shops holding the paid placement tier, from `GET /api/home` (or the showcase list while
  /// the database has none). May be empty - see the guard at the top of [build], which is not
  /// defensive padding: the loop below maps a page index onto this list with `%`, and `% 0` throws.
  final List<HomeShopPreview> shops;

  /// Card + peek. The page is this fraction of the screen; the leftover is split between the two
  /// neighbours, so an edge of the previous and next shop is always visible and the strip reads as
  /// continuous rather than as a single card.
  static const double viewportFraction = 0.84;

  /// Fixed, because a `PageView` needs a bounded height and a carousel whose cards changed height
  /// per shop would jolt as it snapped.
  ///
  /// 232 and not the 216 it was: the card carries a basket price *and* a comparison badge now,
  /// which is one line more than the single price row it replaced. The overflow that caused was
  /// silent in release and a 12px striped bar in debug - worth knowing that a `Column` inside a
  /// fixed-height card fails this way rather than by scrolling.
  static const double cardHeight = 232;

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
    // the opening page has to be an exact multiple of the shop count so the carousel opens on the
    // first shop. that makes it depend on a list which arrives *after* the first frame, and a
    // PageController's initialPage cannot be changed once it is built - so the home screen gives
    // this widget a ValueKey on the list length, which makes flutter build a fresh State (and a
    // fresh controller) the moment the count changes. the `max(1, ...)` only covers the first frame
    // before any shops have loaded, when build returns early anyway.
    _initialPage = _loopOrigin * math.max(1, widget.shops.length);
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
    // nothing to loop over. the home screen already omits the whole section (heading included) in
    // this case, so this is the belt to that braces - but it is a real one: `index % 0` below is a
    // division by zero, not an empty carousel.
    if (widget.shops.isEmpty) return const SizedBox.shrink();

    final strings = Provider.of<LanguageProvider>(context).strings;

    return SizedBox(
      height: VipShopsCarousel.cardHeight,
      child: PageView.builder(
        controller: _controller,
        // unbounded: the builder is asked for whatever page the user swipes to, forever
        itemCount: null,
        padEnds: true,
        itemBuilder: (context, index) {
          final shop = widget.shops[index % widget.shops.length];

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
          // the shop's name lives on the banner, opposite its rating. it used to head the content
          // block below, which meant the tallest, boldest thing on the card sat *under* a large
          // empty image - the eye landed on the placeholder first and the identity second. moving
          // it up pairs the two facts that identify a shop on one line and leaves the content block
          // to do one job: what it costs.
          _Banner(name: shop.name, rating: shop.rating),
          Expanded(
            child: Padding(
              // 14 all round, and 16 at the bottom: the badge is the last thing on the card and
              // needs to sit clear of the edge rather than tucked against it
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

                  // the three below are separated by real gaps rather than by `spaceBetween`. the
                  // old card distributed its slack, so the spacing changed with the content and the
                  // block read as compressed at the top and stranded at the bottom; fixed gaps make
                  // the rhythm the same on every card, and the Spacer takes the leftover.
                  const SizedBox(height: 10),

                  // ListVipShops inner-joins the basket index, so a card in this carousel always
                  // has a price - a paid slot showing a blank is not worth what someone paid for
                  // it. the null branches are still written out because the showcase list and any
                  // future caller are not bound by that query's shape.
                  //
                  // the price is the largest thing in the content block on purpose: it is what the
                  // section is for, and the address above it is context, not the point.
                  if (shop.basketPrice case final basket?)
                    Text(
                      strings.somAmount(basket),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 17,
                        height: 1.15,
                        letterSpacing: -0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                  if (shop.priceTier case final tier?) ...[
                    const SizedBox(height: 9),
                    PriceTierBadge(
                      tier: tier,
                      differencePercent: shop.priceDifferencePercent,
                      strings: strings,
                    ),
                  ],

                  // soaks up whatever is left, so the block stays top-aligned and the bottom
                  // padding above is the real distance to the card's edge
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's cover area: a placeholder where a shop photo will go, with the shop's name at the
/// top-left and its rating at the top-right, on one line.
///
/// **The name is brand orange on the bare placeholder, with no scrim behind it.** A dark gradient
/// across the top was tried and removed: over a pale peach placeholder there is nothing to protect
/// text from, so all it did was put a grey smear across the top third of every card.
///
/// That leaves a real problem for the day photo upload lands - orange text on an arbitrary
/// photograph will not always be legible. The fix then is the treatment already on this card: a
/// white pill, the same as the rating badge on the right, which works over any image and keeps the
/// two ends of the line symmetrical. Adding it now would be solving a problem that does not exist
/// yet against a placeholder that will be deleted.
class _Banner extends StatelessWidget {
  const _Banner({required this.name, required this.rating});

  final String name;
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

            // name and rating on one line: identity on the left, quality on the right, the way a
            // listing card is read.
            Positioned(
              top: 10,
              left: 12,
              right: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 16,
                        height: 1.2,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
