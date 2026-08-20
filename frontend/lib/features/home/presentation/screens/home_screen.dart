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

/// The page gutter every block on this feed shares, header included - so the DOMIX pill, the search
/// bar and every section heading line up down one left edge.
///
/// **10, down from 16, and the number it is really set against is the nav bar's own inset**
/// (`FloatingBottomNavBar`, 22). The bar is *supposed* to look narrower than the page it floats over
/// - that gap is the entire reason it reads as floating rather than as a docked strip - and at 16
/// against 18 the two edges were 2dp apart, which no eye resolves. Widening the content was chosen
/// over narrowing the bar because the bar is five touch targets and the content is not: the feed had
/// room to give and the bar did not.
///
/// **Not applied here.** Each block takes it itself, which is what lets [VipShopsCarousel] opt out
/// and bleed to the screen edges while every heading still lines up.
const EdgeInsets _gutter = EdgeInsets.symmetric(horizontal: 10);

/// The home feed: VIP Магазины, Популярные категории, Лучшие предложения.
///
/// All three read [HomeController], which fetches them together from `GET /api/home`. It is
/// stateful now only because something has to kick that fetch off - the widgets themselves are
/// still pure renderers taking a list.
///
/// **Everything on this screen is either a real row from the database or an empty slot that says so.**
/// There used to be a file of invented shops the controller substituted whenever the backend came
/// back empty, so the app would demo; it is deleted. The two sections that are a fixed number of
/// places draw those places whether or not anything is in them, and the category tiles open onto the
/// real catalogue or onto an empty state.
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
    // deferred past the first frame: loadHome() notifies before its first await, and calling that
    // synchronously from initState trips flutter's "notifyListeners during build" guard - the same
    // fix map_screen.dart and my_shops_screen.dart already carry.
    //
    // this screen lives inside the shell's IndexedStack, so its State survives every tab switch and
    // this runs exactly once per app launch. loadHome() is a no-op on an already-loaded controller
    // anyway, so a rebuild cannot turn into a second fetch.
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

  /// The same screen a map pin opens. Navigation lives here rather than inside the carousel and the
  /// rows, so a card stays a thing that reports a tap instead of a thing that knows about routes.
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
          // the header sits on the shared gutter like every other block rather than carrying its own
          // copy of the number - two constants that have to agree is how the DOMIX pill ends up a
          // few pixels out of line with the search bar under it
          const Padding(padding: _gutter, child: HomeHeader()),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryOrange,
              onRefresh: () => home.loadHome(force: true),
              // no horizontal padding here on purpose: each block applies the shared gutter itself,
              // which lets the carousel opt out and bleed to the screen edges while every heading
              // still lines up with the DOMIX pill and the search bar above it
              child: SingleChildScrollView(
                // AlwaysScrollable wrapping the bouncing physics, not replacing it: content that
                // fits the viewport exactly has nothing to overscroll, and the pull gesture is
                // never recognised without this
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

  /// The feed below the search bar.
  ///
  /// **All three sections always draw, whatever the database holds**, and only the very first paint
  /// (before the fetch lands) is different.
  ///
  /// VIP Магазины is five slots whether or not any are sold; Лучшие предложения is four segments -
  /// every shop category, always - over fifteen places each; Популярные категории is always all
  /// twelve tiles. **A section that vanished when it was empty read as a screen missing a chunk of
  /// itself**, and the empty places are the honest version: this is the shape the feed has, and it
  /// fills itself in as shops finish pricing.
  ///
  /// None of the headings carries a "see all" action. Each already shows everything it has: the VIP
  /// carousel loops endlessly in both directions, the categories grid pages through all twelve, and
  /// Лучшие предложения is a top-N with no longer tail to open.
  List<Widget> _sections(HomeController home, AppLocalizations strings) {
    // the very first paint, before the fetch has come back. a spinner rather than empty sections,
    // which would flash "nothing here" for a moment and then fill in - and, now that the empty slots
    // are real content, would flash a full screen of them.
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
      // keyed on the number of slots, which is a constant - so in practice this State is built once
      // and never replaced. it stays because the ring grows if the backend ever sends more
      // placements than this build expects, and a PageController's initialPage (which is derived
      // from the ring's size) cannot be changed after it is built.
      VipShopsCarousel(
        key: ValueKey(vipSlots.length),
        slots: vipSlots,
        onShopTap: _openShop,
      ),

      // no panel behind this section any more: the white surface moved onto the individual tiles
      // (see PopularCategoriesGrid), so the feed is container-free again and this heading sits on
      // the gutter like every other one.
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

      // the load failed. drawn *below* the sections rather than instead of them, because the five
      // VIP slots and the twelve tiles are still true - they are the shape of the screen, not data
      // that came back wrong - and replacing the whole feed with an error would hide a working app
      // behind one failed request.
      //
      // danger-coloured with a retry, the same treatment ProductResultsView and my-shops use: a
      // failure must not look like a friendly "nothing here yet", because the two want opposite
      // things from the reader.
      if (home.loadError case final error?) ...[
        const SizedBox(height: 40),
        Padding(
          padding: _gutter,
          child: EmptyStateView(
            icon: CupertinoIcons.wifi_exclamationmark,
            iconColor: AppColors.danger,
            iconBackground: AppColors.dangerSoft,
            title: strings.homeLoadError,
            subtitle: error,
            action: PrimaryActionButton(
              label: strings.retryButtonShort,
              onTap: () => home.loadHome(force: true),
            ),
          ),
        ),
      ],

      // **there is deliberately no "пока нет магазинов" block under this any more.** It sat here
      // while an empty feed meant empty *sections*, and it stopped earning its place the moment both
      // sections started drawing their open places: a screenful of designed-empty cards followed by a
      // notice apologising for being empty says the same thing twice, and the second time it reads as
      // something being wrong. The open places are the answer to "why is this screen bare" - they
      // fill themselves in as shops finish pricing. A *failure* still gets the block above, because
      // that one is not a state the feed can explain by itself.
    ];
  }
}
