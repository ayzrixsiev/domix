import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/home/data/home_content.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/category_products_screen.dart';
import 'package:frontend/features/home/presentation/widgets/home_header.dart';
import 'package:frontend/features/home/presentation/widgets/section_header.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/home/presentation/widgets/vip_shops_carousel.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// The page gutter every block on this feed shares, header included, so the DOMIX pill, the search
/// bar and every heading line up down one left edge.
///
/// 10, set against the nav bar's own inset (22): the bar has to look narrower than the page it
/// floats over. **Not applied here** - each block takes it itself, which lets [VipShopsCarousel] opt
/// out and bleed to the screen edges.
const EdgeInsets _gutter = EdgeInsets.symmetric(horizontal: 10);

/// How far the feed has to be dragged before letting go actually refreshes, and how tall the gap
/// stays while it does. The trigger sits well above the resting extent so the gesture has somewhere
/// to travel - pulling past the trigger is what fills the ring.
const double _refreshTriggerDistance = 110;
const double _refreshIndicatorExtent = 70;

/// The home feed: VIP Магазины, Популярные категории, Лучшие предложения - all three from one
/// `GET /api/home`. **Everything here is either a real row from the database or an empty slot that
/// says so.**
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
  });

  final bool showScaffold;
  final double bottomPadding;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // deferred past the first frame: loadHome() notifies before its first await, which from initState
    // trips the "notifyListeners during build" guard. this State survives every tab switch, so it runs
    // once per launch - and loadHome() is a no-op on an already-loaded controller anyway.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HomeController>().loadHome();
    });
  }

  void _openCategory(ProductCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategoryProductsScreen(category: category)),
    );
  }

  /// Navigation lives here rather than inside the carousel and the rows, so a card stays a thing that
  /// reports a tap instead of one that knows about routes.
  void _openShop(Shop shop) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShopCardScreen(shop: shop)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final home = Provider.of<HomeController>(context);

    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the header sits on the shared gutter rather than carrying its own copy of the number.
          // it lives *outside* the scroll view, which is what makes the refresh gap open between it
          // and the search bar rather than pushing the whole page down.
          const Padding(padding: _gutter, child: HomeHeader()),
          Expanded(
            // slivers rather than a SingleChildScrollView, because the refresh control below is one:
            // it has to be able to set its own height frame by frame to open and close the gap.
            child: CustomScrollView(
              // AlwaysScrollable wrapping the bouncing physics, not replacing it: content that exactly fits the
              // viewport has nothing to overscroll and the pull gesture is never recognised. Bouncing is also
              // what gives the pull somewhere to travel on Android, where the default clamps at zero.
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                // **Cupertino's control rather than RefreshIndicator's floating circle.** The circle
                // hovers *over* the content and snaps away the instant the future completes. This one
                // opens a gap, holds the spinner inside the gap it opened, and then animates that gap
                // shut on its own - the spinner stays lit the whole way down and leaves with it.
                CupertinoSliverRefreshControl(
                  refreshTriggerPullDistance: _refreshTriggerDistance,
                  refreshIndicatorExtent: _refreshIndicatorExtent,
                  builder: _buildRefreshIndicator,
                  onRefresh: () => home.loadHome(force: true),
                ),
                // **no title block here.** the home feed already names itself: the DOMIX wordmark
                // sits in the header row above, and a second «Главная» under it was one label too
                // many on the one screen that never needed telling apart from another.
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      SizedBox(height: 14),
                      Padding(padding: _gutter, child: SearchAndLikeBar()),
                    ],
                  ),
                ),
                ..._feed(home, strings),
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }

    return Scaffold(backgroundColor: AppColors.background, body: body);
  }

  /// What sits inside the gap while it is open.
  ///
  /// One spinner family for the whole app: the same [CircularProgressIndicator] the cold start
  /// draws, in brand orange. It is *determinate* while the finger is still down - the ring fills as
  /// the gap opens, so the gesture shows its own progress and letting go early is visibly early -
  /// and switches to the indeterminate spin once the request is actually in flight.
  Widget _buildRefreshIndicator(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double triggerDistance,
    double indicatorExtent,
  ) {
    final progress = (pulledExtent / triggerDistance).clamp(0.0, 1.0);
    final isDragging = mode == RefreshIndicatorMode.drag;

    return Center(
      child: Opacity(
        // fades in with the pull rather than appearing at full strength in a 2px gap
        opacity: isDragging ? progress : 1,
        child: SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.primaryOrange,
            value: isDragging ? progress : null,
          ),
        ),
      ),
    );
  }

  /// The feed below the search bar, as slivers.
  ///
  /// Three states, and only ever one of them on screen: starting up, failed, or the feed itself.
  /// **A failure replaces the feed rather than being appended under it** - five empty VIP slots and
  /// fifteen empty rows followed by "не удалось загрузить" reads as a working screen with a
  /// complaint stapled to the bottom, and buries the retry a full scroll away from the problem.
  List<Widget> _feed(HomeController home, AppLocalizations strings) {
    // the very first paint, before the fetch has come back. a spinner rather than a full screen of
    // empty slots flashing past and then filling in.
    if (!home.hasLoaded) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
        ),
      ];
    }

    if (home.loadFailed) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: _gutter,
              child: EmptyStateView(
                icon: CupertinoIcons.wifi_exclamationmark,
                iconColor: AppColors.danger,
                iconBackground: AppColors.dangerSoft,
                title: strings.homeLoadError,
                // a written sentence, never the exception - see AppLocalizations.loadErrorHint
                subtitle: strings.loadErrorHint,
                action: PrimaryActionButton(
                  label: strings.retryButtonShort,
                  onTap: () => home.loadHome(force: true),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    final vipSlots = vipSlotRing(home.vipShops, slotCount: VipShopsCarousel.slotCount);

    return [
      // one adapter holding the whole feed rather than a lazy SliverList: the three sections are a
      // fixed, short page - five carousel slots, twelve tiles, fifteen rows - and building them
      // together is what the Column did before the refresh control needed slivers here. Going lazy
      // would be a different screen (headings below the fold stop existing until scrolled to), and
      // that is not what this change is for.
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // **14, against the 26 between the sections below.** This gap is not between two
            // sections: above it is the search bar, which is a control rather than content, and the
            // VIP strip is the first thing on the page worth reading. 26 under the capsule left the
            // paid placement floating in the middle of the screen.
            const SizedBox(height: 14),
            Padding(padding: _gutter, child: SectionHeader(title: strings.vipShops)),
            const SizedBox(height: 12),
            // keyed on the slot count, so the State is rebuilt if the ring ever grows - a PageController's
            // initialPage is derived from that size and cannot be changed afterwards
            VipShopsCarousel(
              key: ValueKey(vipSlots.length),
              slots: vipSlots,
              onShopTap: _openShop,
            ),

            // the section's own panel is gone: the white surface moved onto the individual cards
            //
            // **12 where every other section takes 26, and not a number to normalise back.** The
            // carousel does not end at its card: under it come 12dp of gap and a row of dots, so
            // the usual 26 put 47dp of air between the VIP card and this heading - twice what sits
            // between any other two sections, and it read as a hole in the feed.
            const SizedBox(height: 10),
            Padding(
              padding: _gutter,
              child: SectionHeader(title: strings.popularCategories),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: _gutter,
              child: PopularCategoriesGrid(onCategoryTap: _openCategory),
            ),

            const SizedBox(height: 26),
            Padding(padding: _gutter, child: SectionHeader(title: strings.bestOffersTitle)),
            const SizedBox(height: 12),
            Padding(
              padding: _gutter,
              child: BestOffersList(groups: home.bestOffers, onShopTap: _openShop),
            ),

            SizedBox(height: widget.bottomPadding),

            // **no "пока нет магазинов" block here on purpose**: a screenful of designed-empty cards followed
            // by a notice apologising for being empty says the same thing twice. the open places are the
            // answer. a *failure* is the branch above, which takes the screen instead of sharing it.
          ],
        ),
      ),
    ];
  }
}
