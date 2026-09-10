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
          // the header sits on the shared gutter rather than carrying its own copy of the number
          const Padding(padding: _gutter, child: HomeHeader()),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryOrange,
              onRefresh: () => home.loadHome(force: true),
              // no horizontal padding here on purpose: each block applies the gutter itself, which lets the
              // carousel bleed to the screen edges while every heading still lines up
              child: SingleChildScrollView(
                // AlwaysScrollable wrapping the bouncing physics, not replacing it: content that exactly fits the
                // viewport has nothing to overscroll and the pull gesture is never recognised
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 14),
                    const Padding(padding: _gutter, child: SearchAndLikeBar()),
                    ..._sections(home, strings),
                    SizedBox(height: widget.bottomPadding),
                  ],
                ),
              ),
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

  /// The feed below the search bar. **All three sections always draw, whatever the database holds** -
  /// a section that vanished when empty read as a screen missing a chunk of itself. No heading carries
  /// a "see all": each one already shows everything it has.
  List<Widget> _sections(HomeController home, AppLocalizations strings) {
    // the very first paint, before the fetch has come back. a spinner rather than a full screen of
    // empty slots flashing past and then filling in.
    if (!home.hasLoaded) {
      return const [
        SizedBox(height: 64),
        Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
      ];
    }

    final vipSlots = vipSlotRing(home.vipShops, slotCount: VipShopsCarousel.slotCount);

    return [
      const SizedBox(height: 26),
      Padding(padding: _gutter, child: SectionHeader(title: strings.vipShops)),
      const SizedBox(height: 12),
      // keyed on the slot count, so the State is rebuilt if the ring ever grows - a PageController's
      // initialPage is derived from that size and cannot be changed afterwards
      VipShopsCarousel(
        key: ValueKey(vipSlots.length),
        slots: vipSlots,
        onShopTap: _openShop,
      ),

      // no panel behind this section: the white surface moved onto the individual tiles
      const SizedBox(height: 26),
      Padding(padding: _gutter, child: SectionHeader(title: strings.popularCategories)),
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

      // drawn *below* the sections rather than instead of them: the five VIP slots and the twelve tiles
      // are the shape of the screen, not data that came back wrong. danger-coloured with a retry, since
      // a failure must not look like a friendly "nothing here yet".
      if (home.loadFailed) ...[
        const SizedBox(height: 40),
        Padding(
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
      ],

      // **no "пока нет магазинов" block here on purpose**: a screenful of designed-empty cards followed
      // by a notice apologising for being empty says the same thing twice. the open places are the
      // answer. a *failure* still gets the block above, which the feed cannot explain by itself.
    ];
  }
}
