import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/features/home/presentation/controllers/home_controller.dart';
import 'package:frontend/features/home/presentation/screens/category_products_screen.dart';
import 'package:frontend/features/home/presentation/widgets/home_header.dart';
import 'package:frontend/features/home/presentation/widgets/section_header.dart';
import 'package:frontend/features/home/presentation/widgets/best_offers.dart';
import 'package:frontend/features/home/presentation/widgets/popular_categories_grid.dart';
import 'package:frontend/features/home/presentation/widgets/search_and_like_bar.dart';
import 'package:frontend/features/home/presentation/widgets/vip_shops_carousel.dart';
import 'package:frontend/features/products/data/product_category.dart';

/// the page gutter every block shares - the same 16 the header and search bar sit on, so section
/// headings line up with them down the left edge
const EdgeInsets _gutter = EdgeInsets.symmetric(horizontal: 16);

/// The home feed: VIP Магазины, Популярные категории, Лучшие предложения.
///
/// All three read [HomeController], which fetches them together from `GET /api/home`. It is
/// stateful now only because something has to kick that fetch off - the widgets themselves are
/// still pure renderers taking a list.
///
/// While the database has no shops, the controller substitutes the showcase rows in
/// `home_showcase_content.dart`, and nothing here can tell. That is deliberate: the sections below
/// contain no fallback logic to remember to delete.
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

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final home = Provider.of<HomeController>(context);

    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HomeHeader(),
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
  /// **A section with nothing in it is omitted entirely, heading and all.** A "VIP Магазины"
  /// heading over blank space is worse than no heading: it tells a customer the app is broken
  /// rather than that nobody has bought a placement yet. The categories grid is the exception - it
  /// always renders all twelve tiles, because the tiles are the vocabulary and a grid that changed
  /// shape depending on what happened to be stocked would be a different screen every load.
  ///
  /// None of the three headings carries a "see all" action. Each already shows everything it has:
  /// the VIP carousel loops endlessly in both directions, the categories grid pages through all
  /// twelve, and Лучшие предложения is a top-N with no longer tail to open.
  List<Widget> _sections(HomeController home, AppLocalizations strings) {
    // the very first paint, before the fetch has come back. a spinner rather than empty sections,
    // which would flash "nothing here" for a moment and then fill in.
    if (!home.hasLoaded) {
      return const [
        SizedBox(height: 64),
        Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
      ];
    }

    return [
      if (home.vipShops.isNotEmpty) ...[
        const SizedBox(height: 26),
        Padding(padding: _gutter, child: SectionHeader(title: strings.vipShops)),
        const SizedBox(height: 12),
        // keyed on the shop count: the carousel opens on a page that is an exact multiple of that
        // count, and a PageController's initialPage cannot change after it is built. a new key
        // makes flutter build a fresh State with a fresh controller when the list arrives.
        VipShopsCarousel(
          key: ValueKey(home.vipShops.length),
          shops: home.vipShops,
        ),
      ],

      const SizedBox(height: 26),
      Padding(
        padding: _gutter,
        child: _SectionPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: strings.popularCategories),
              const SizedBox(height: 14),
              PopularCategoriesGrid(onCategoryTap: _openCategory),
            ],
          ),
        ),
      ),

      if (home.bestOffers.isNotEmpty) ...[
        const SizedBox(height: 26),
        Padding(padding: _gutter, child: SectionHeader(title: strings.bestOffersTitle)),
        const SizedBox(height: 12),
        Padding(padding: _gutter, child: BestOffersList(groups: home.bestOffers)),
      ],

      // both shop sections empty and the load is done: there genuinely are no shops yet. this is
      // unreachable while kShowcaseFallbackEnabled is true, and is what the screen becomes the day
      // the showcase rows are deleted.
      if (home.vipShops.isEmpty && home.bestOffers.isEmpty) ...[
        const SizedBox(height: 40),
        Padding(
          padding: _gutter,
          child: EmptyStateView(
            icon: CupertinoIcons.bag,
            title: strings.noShopsYet,
            subtitle: home.loadError ?? strings.noShopsYetHint,
          ),
        ),
      ],
    ];
  }
}

// The white panel behind the categories grid.
//
// The home feed is otherwise deliberately container-free - an earlier pass wrapped every section
// in a panel and it was removed, so this is not a return to that. Only the categories grid gets
// one, because it is the one section made of small tinted tiles rather than self-contained cards:
// without a surface behind them the tiles read as loose objects scattered on the page rather
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
