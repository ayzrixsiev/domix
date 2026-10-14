import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/favorites/presentation/controllers/favorites_controller.dart';
import 'package:frontend/features/favorites/presentation/favorite_action.dart';
import 'package:frontend/features/home/data/category_product.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/data/product_section.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/catalogue_search_bar.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/price_tier.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/data/stores_repository.dart';
import 'package:frontend/features/stores/presentation/widgets/shop_category_avatar.dart';
import 'package:frontend/features/stores/presentation/widgets/shop_category_banner.dart';
import 'package:frontend/core/widgets/app_page_header.dart';
import 'package:frontend/core/widgets/circle_icon_button.dart';

// one shop, in full. every route into a shop ends here - a map pin, a VIP card, a Лучшие
// предложения row.
//
// two chromes over identical content: a draggable sheet over the map (showShopCardSheet), so comparing
// three nearby shops does not rebuild the map three times, and a full-screen route everywhere else.
// both are a CustomScrollView, which is what makes the catalogue a sliver.
//
// the details sit on one white surface and the catalogue keeps the page under it: above is this shop,
// below is its goods.
class ShopCardScreen extends StatelessWidget {
  const ShopCardScreen({super.key, required this.shop});

  // the whole shop, never an id to look up: every entry point already holds one, so the card paints
  // complete on its first frame
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    // no SafeArea at the top - the cover runs under the status bar, which is why its own top is painted
    // near-white and the overlay style is asked for here rather than inherited from an absent AppBar
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: ShopCardView(shop: shop, chrome: ShopCardChrome.route),
      ),
    );
  }
}

// the same card opened from something holding only a shop id - the one route that has to fetch. a
// 404 gets its own sentence: the shop was deleted while its cement was on screen.
class ShopByIdScreen extends StatefulWidget {
  const ShopByIdScreen({super.key, required this.shopId, this.repository});

  final int shopId;

  /// Injectable for tests; nothing in the app passes it.
  final StoresRepository? repository;

  @override
  State<ShopByIdScreen> createState() => _ShopByIdScreenState();
}

class _ShopByIdScreenState extends State<ShopByIdScreen> {
  late final StoresRepository _repo = widget.repository ?? StoresRepository();

  Shop? _shop;
  bool _isLoading = true;

  // the one outcome worth a *different* sentence - nothing to retry. everything else is the retryable
  // branch, which never carries the exception onto the screen.
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _load();
    // the catalogue is fetched alongside the shop rather than after it: the id is all it needs, and
    // waiting for the shop first cost a whole extra round trip on the most common way into a shop -
    // tapping a search result. the card's own call then finds it in flight or done and does nothing.
    // deferred a frame for the reason ShopCardView's is: loadProducts notifies before its first await.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductsController>().loadProducts(widget.shopId);
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _gone = false;
    });

    try {
      final shop = await _repo.fetchShop(widget.shopId);
      // the request outlives the screen if the reader backs out, so `mounted` is checked after the await
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _gone = shop == null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // the log is the only place the real exception goes
      debugPrint('ShopByIdScreen: could not load shop ${widget.shopId}: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final shop = _shop;

    // loaded: hand off to the same widget every other entry point renders, chrome and all
    if (shop != null) return ShopCardScreen(shop: shop);

    return Scaffold(
      backgroundColor: AppColors.background,
      // back and nothing else: this screen has nothing to title itself with until the shop arrives,
      // and by then it has been replaced
      appBar: const AppPageHeader.custom(),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: AppColors.primaryOrange)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _gone
                    ? EmptyStateView(
                        icon: CupertinoIcons.building_2_fill,
                        title: strings.shopGoneTitle,
                        subtitle: strings.shopGoneBody,
                      )
                    : EmptyStateView(
                        icon: CupertinoIcons.wifi_exclamationmark,
                        iconColor: AppColors.danger,
                        iconBackground: AppColors.dangerSoft,
                        title: strings.shopLoadError,
                        action: PrimaryActionButton(
                          label: strings.retryButtonShort,
                          onTap: _load,
                        ),
                      ),
              ),
      ),
    );
  }
}

// so no caller has to know that opening a shop from an id costs a fetch
Future<void> openShopById(BuildContext context, int shopId) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ShopByIdScreen(shopId: shopId)),
  );
}

// opens the shop card as the map's draggable sheet. the numbers are the behaviour: 0.92 leaves a
// strip of map showing, 0.5 with shouldCloseOnMinExtent is why there is no close button, and `snap`
// stops it sitting at 70%. the ScrollController handed to the builder must end up on the card's own
// scroll view - it is what lets a drag hand itself from the list to the sheet.
Future<void> showShopCardSheet(BuildContext context, Shop shop) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // the sheet paints its own surface, so the route's background must not draw a square-cornered one
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      snap: true,
      // false: `true` fills the viewport with a transparent slab that swallows every tap meant for the
      // barrier, so the map would stop being dismissable by tapping it
      expand: false,
      builder: (context, scrollController) => ShopCardView(
        shop: shop,
        chrome: ShopCardChrome.sheet,
        scrollController: scrollController,
      ),
    ),
  );
}

/// How the card arrived - see the class comment on [ShopCardScreen].
enum ShopCardChrome { route, sheet }

/// The card's content, and the only place it is written.
class ShopCardView extends StatefulWidget {
  const ShopCardView({
    super.key,
    required this.shop,
    required this.chrome,
    this.scrollController,
  });

  final Shop shop;
  final ShopCardChrome chrome;

  // must end up on the scroll view - it is what lets a drag hand itself from the list to the sheet.
  // null in the pushed route.
  final ScrollController? scrollController;

  @override
  State<ShopCardView> createState() => _ShopCardViewState();
}

// the one horizontal inset: text, rules, the field and the grid all sit on it, so a rule ends
// exactly where a line of text does
const double _gutter = 16;

class _ShopCardViewState extends State<ShopCardView> {
  // held here so the heading, the field and the grid all read one value
  final TextEditingController _search = TextEditingController();

  String _query = '';

  // null is «Все товары»
  ProductSection? _section;

  // below this the search *field* is not drawn: two per row means eight is about one screenful, and
  // a field over a list already entirely on screen filters nothing. the sections do not go with it
  static const int _searchThreshold = 8;

  bool get _isSheet => widget.chrome == ShopCardChrome.sheet;

  @override
  void initState() {
    super.initState();
    // deferred past the first frame: loadProducts notifies before its first await, and doing that while
    // this element is mounting is "setState() called during build"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductsController>().loadProducts(widget.shop.id);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // the catalogue is the only thing that changes while this screen is open - an owner pricing
  // products in another session
  Future<void> _refresh() {
    return context.read<ProductsController>().loadProducts(widget.shop.id, force: true);
  }

  Future<void> _dial() async {
    if (!await _tryOpen(Uri.parse('tel:${widget.shop.contactPhone}'))) _reportNothingToOpenWith();
  }

  // **plain text, not a link to us**: there is no page per shop and no deep link into the app, so a
  // url would be a promise the build cannot keep. the four lines are what somebody needs to find the
  // place - the last one opens in any browser, which is the only part that has to work on a phone
  // without Domix on it.
  Future<void> _share() async {
    final shop = widget.shop;
    final text = '${shop.name}\n'
        '${shop.address}\n'
        '${shop.contactPhone}\n'
        'https://yandex.uz/maps/?pt=${shop.longitude},${shop.latitude}&z=17';

    try {
      // no sharePositionOrigin: it positions the popover an iPad anchors the sheet to, and this app
      // ships android only
      await SharePlus.instance.share(ShareParams(text: text, subject: shop.name));
    } catch (e) {
      debugPrint('ShopCardView: could not share shop ${shop.id}: $e');
      _reportNothingToOpenWith();
    }
  }

  // the number is the one thing on this card somebody wants in another app, and a long-press on a
  // Text selects nothing
  Future<void> _copyPhone() async {
    await Clipboard.setData(ClipboardData(text: widget.shop.contactPhone));
    if (!mounted) return;
    _toast(Provider.of<LanguageProvider>(context, listen: false).strings.phoneCopied);
  }

  // hands the coordinates to whatever maps app the phone has: `geo:` is a platform scheme, so the
  // system shows a chooser, where a yandex url opens a browser on a phone with only Google Maps.
  // `geo:` cannot express "route to it", so the web url underneath covers that and a phone with no
  // maps app. both need a `<queries>` entry in AndroidManifest.xml - Android 11 package visibility.
  Future<void> _route() async {
    final shop = widget.shop;
    final point = '${shop.latitude},${shop.longitude}';
    // parentheses delimit the label in a geo: uri, and Uri.encodeComponent leaves them alone
    final label = Uri.encodeComponent(shop.name.replaceAll(RegExp(r'[()]'), ''));

    if (await _tryOpen(Uri.parse('geo:$point?q=$point($label)'))) return;
    if (await _tryOpen(Uri.parse('https://yandex.uz/maps/?rtext=~$point&rtt=auto'))) return;
    _reportNothingToOpenWith();
  }

  // **the return value of launchUrl is the signal, not canLaunchUrl**, which answers false for
  // launchable links unless every scheme is declared - and throws rather than returning false, so the
  // catch is part of the answer
  Future<bool> _tryOpen(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('ShopCardView: could not open $uri: $e');
      return false;
    }
  }

  void _reportNothingToOpenWith() {
    if (!mounted) return;
    _toast(Provider.of<LanguageProvider>(context, listen: false).strings.couldNotOpenExternalApp);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  // priced rows only: an unpriced row answers no question for a customer, and a fresh shop would bury
  // the handful that are priced under a hundred that are not
  List<Product> _pricedProducts(ProductsController controller) => [
        for (final product in controller.productsFor(widget.shop.id))
          if (product.hasPrice) product,
      ];

  // name and description - the size lives in the description now. not the unit: "шт" would match
  // most of the list.
  List<Product> _matching(List<Product> priced) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return priced;
    return [
      for (final product in priced)
        if ('${product.name} ${product.specs}'.toLowerCase().contains(query)) product,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<ProductsController>(context);
    final shop = widget.shop;

    final priced = _pricedProducts(controller);
    // chips from the whole priced list, not the search's, so they do not jump about while typing
    final sections = sectionsOf(priced);
    final section = sections.contains(_section) ? _section : null;
    final matches = productsBySection(_matching(priced), only: section);
    final isFirstLoad = controller.isLoadingFor(shop.id) && !controller.hasLoaded(shop.id);

    // the pushed route draws its cover under the status bar, so the picture is that much taller for the
    // same 240 of it to show. the sheet is opened with useSafeArea and takes the plain height.
    final coverHeight = ShopCategoryBanner.defaultHeight +
        (_isSheet ? 0 : MediaQuery.paddingOf(context).top);

    const gutter = EdgeInsets.symmetric(horizontal: _gutter);

    final scrollView = CustomScrollView(
      controller: widget.scrollController,
      // onDrag: on the sheet this is the same drag that would otherwise put the sheet away with the
      // keyboard still on top of it
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        // no padding around the cover: full width, hard against the top
        SliverToBoxAdapter(
          child: _ShopHeader(
            shop: shop,
            strings: strings,
            coverHeight: coverHeight,
            onCall: _dial,
            onRoute: _route,
            onCopyPhone: _copyPhone,
          ),
        ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 24)),
          sliver: SliverToBoxAdapter(
            child: _ProductsHeading(count: priced.length, strings: strings),
          ),
        ),
        // the field and the sections are two separate questions - a short catalogue can still be
        // split into sections, and then the bar is the «Категории» button on its own
        if (priced.length >= _searchThreshold || sections.length > 1)
          SliverPadding(
            padding: gutter.add(const EdgeInsets.only(top: 14)),
            sliver: SliverToBoxAdapter(
              child: CatalogueSearchBar(
                searchable: priced.length >= _searchThreshold,
                controller: _search,
                products: priced,
                selected: section,
                onSelected: (value) => setState(() => _section = value),
                strings: strings,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 14)),
          sliver: _ProductsSliver(
            products: matches,
            shopName: shop.name,
            strings: strings,
            isFirstLoad: isFirstLoad,
            // three empty states, and telling them apart is the point: the request failed, the shop has priced
            // nothing, or this search matched nothing
            hasFailed: controller.loadFailedFor(shop.id),
            isFiltered: _query.trim().isNotEmpty || section != null,
          ),
        ),
        // a tail so the last row is not flush against the bottom, plus the system inset. viewInsets is in
        // there for the sheet: its Scaffold cannot resize for the keyboard, so this is what gives
        // ensureVisible somewhere to scroll the focused field to.
        SliverToBoxAdapter(
          child: SizedBox(
            height: 28 +
                MediaQuery.paddingOf(context).bottom +
                MediaQuery.viewInsetsOf(context).bottom,
          ),
        ),
      ],
    );

    return switch (widget.chrome) {
      // **no RefreshIndicator on the sheet**: a pull at the top is the gesture that puts the sheet away,
      // and a spinner competing for it would refresh or close depending on how far the thumb travelled
      ShopCardChrome.route => Stack(
          children: [
            RefreshIndicator(
              color: AppColors.primaryOrange,
              onRefresh: _refresh,
              child: scrollView,
            ),
            // clear of the status bar the cover now runs under
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              // the page gutter, which is where every other back disc in the app starts
              left: CircleIconButton.gutterInset,
              // floating: it hovers over the cover rather than sitting in a bar
              child: const CircleBackButton(floating: true),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: CircleIconButton.gutterInset,
              child: _ShareButton(onTap: _share, strings: strings),
            ),
          ],
        ),
      ShopCardChrome.sheet => _SheetSurface(
          onShare: _share,
          strings: strings,
          child: scrollView,
        ),
    };
  }
}

// the same disc at both ends of the cover, so the sheet and the pushed route offer the shop the
// same way
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap, required this.strings});

  final VoidCallback onTap;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return CircleIconButton(
      icon: LucideIcons.share,
      floating: true,
      tooltip: strings.shareShopTooltip,
      onTap: onTap,
    );
  }
}

// the sheet's surface: rounded top, page background, a grabber.
//
// the Scaffold is not decoration - a modal sheet is a route with no Scaffold, so a showSnackBar from
// inside it lands in the map's, underneath the sheet. the grabber floats over the content so the
// cover can reach the top edge, and IgnorePointer lets a drag on it fall through to the scroll view.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child, required this.onShare, required this.strings});

  final Widget child;
  final VoidCallback onShare;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // must be the *only* scrollable the sheet's controller reaches - that is what hands a drag between
            // the list and the sheet
            Positioned.fill(child: child),
            const Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(child: Center(child: _SheetGrabber())),
            ),
            // there is no back disc on the sheet - a drag down is the way out - so the right end is
            // the only control on the cover here
            Positioned(
              top: 14,
              right: CircleIconButton.gutterInset,
              child: _ShareButton(onTap: onShare, strings: strings),
            ),
          ],
        ),
      ),
    );
  }
}

// translucent black rather than trackGrey: it lies on the cover, whose top is near-white
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0x33101828),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// the cover, the white surface that climbs over it, and the mark sitting on the seam between them.
//
// the three are one widget because the geometry is one sum: the surface is lifted [_overlap] into
// the cover, and the mark is centred on exactly that line. drawn in this order, so the surface
// covers the cover's bottom edge and the mark covers the surface's top.
class _ShopHeader extends StatelessWidget {
  const _ShopHeader({
    required this.shop,
    required this.strings,
    required this.coverHeight,
    required this.onCall,
    required this.onRoute,
    required this.onCopyPhone,
  });

  final Shop shop;
  final AppLocalizations strings;
  final double coverHeight;
  final VoidCallback onCall;
  final VoidCallback onRoute;
  final VoidCallback onCopyPhone;

  /// how far the white surface climbs into the cover. enough for its [AppRadius.lg] corners to read
  /// as a sheet laid over a picture rather than as a seam that happens to be curved.
  static const double _overlap = 26;

  @override
  Widget build(BuildContext context) {
    const avatar = ShopCategoryAvatar.defaultSize;
    final surfaceTop = coverHeight - _overlap;

    return Stack(
      // the Padding is the only unpositioned child, so it is what gives the stack its height
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ShopCategoryBanner(category: shop.category, height: coverHeight),
        ),
        Padding(
          padding: EdgeInsets.only(top: surfaceTop),
          child: _DetailsSurface(
            shop: shop,
            strings: strings,
            onCall: onCall,
            onRoute: onRoute,
            onCopyPhone: onCopyPhone,
          ),
        ),
        Positioned(
          left: _gutter,
          top: surfaceTop - avatar / 2,
          child: ShopCategoryAvatar(category: shop.category),
        ),
      ],
    );
  }
}

// everything the card says about the shop itself, on one white surface - three rounded cards used to
// do this and made a card about one business read as three things.
//
// **the price section is skipped entirely when there is no basket**: a customer is not the audience
// for another business's unfinished admin.
class _DetailsSurface extends StatelessWidget {
  const _DetailsSurface({
    required this.shop,
    required this.strings,
    required this.onCall,
    required this.onRoute,
    required this.onCopyPhone,
  });

  final Shop shop;
  final AppLocalizations strings;
  final VoidCallback onCall;
  final VoidCallback onRoute;
  final VoidCallback onCopyPhone;

  @override
  Widget build(BuildContext context) {
    final basket = shop.basketPrice;
    final tier = shop.priceTier;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Identity(shop: shop, strings: strings),
          // one condition, not two: a shop is in the index only with its whole template priced, so
          // basketPrice and priceTier are both present or both absent
          if (basket != null && tier != null) ...[
            const _Rule(),
            _BasketPrice(shop: shop, basket: basket, tier: tier, strings: strings),
          ],
          const _Rule(),
          _Contacts(
            shop: shop,
            strings: strings,
            onCall: onCall,
            onRoute: onRoute,
            onCopyPhone: onCopyPhone,
          ),
        ],
      ),
    );
  }
}

// inset from both edges, so it reads as a rule under a block of text rather than a seam between two
// panels. trackGrey rather than `hairline`, which on white is about a 1.08:1 step and never appears.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: _gutter),
      color: AppColors.trackGrey,
    );
  }
}

// whose card this is: the kind of shop, its name, where it is. the name is here rather than on the
// cover, which has nowhere that white text is safe and nowhere that dark text is either - and the
// category is an eyebrow rather than a chip, since the glyph is already on the mark.
//
// **the eyebrow and the name are indented past [ShopCategoryAvatar], which is not in this widget**:
// the mark is drawn over the surface by `_ShopHeader`, so nothing here lays it out and the gap has
// to be held open by hand. the address below it is full width - the mark's lower half ends above it.
class _Identity extends StatelessWidget {
  const _Identity({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  /// the mark's own width plus the gap after it
  static const double _markInset = ShopCategoryAvatar.defaultSize + 14;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 18, _gutter, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: _markInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        shop.category.label(strings).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          height: 1.2,
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // the placement mark, small enough not to compete with the name. not a capsule - a pill beside an
                    // eyebrow is a chip, and this block was rebuilt to be rid of chips.
                    if (shop.isVip) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.star_rounded, color: AppColors.primaryOrange, size: 15),
                      const SizedBox(width: 3),
                      const Text(
                        'VIP',
                        style: TextStyle(
                          color: AppColors.primaryOrange,
                          fontSize: 11.5,
                          height: 1.2,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  shop.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 23,
                    height: 1.16,
                    letterSpacing: -0.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(CupertinoIcons.location_solid, color: AppColors.textFaint, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shop.address,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// **the comparison first, the number second** - the reverse of a price tag, and the point of the
// product: «на 4% дешевле рынка» is what a customer came for and «4 850 000 сум» is what it is 4%
// of. the caption sits under the number, since the number is what the eye should land on.
class _BasketPrice extends StatelessWidget {
  const _BasketPrice({
    required this.shop,
    required this.basket,
    required this.tier,
    required this.strings,
  });

  final Shop shop;
  final int basket;
  final PriceTier tier;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 18, _gutter, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the full sentence rather than the compact form: this is where somebody who tapped a pin reading
          // "−4%" finds out what those four characters meant
          PriceTierBadge(
            tier: tier,
            differencePercent: shop.priceDifferencePercent,
            strings: strings,
            size: PriceTierBadgeSize.headline,
          ),
          const SizedBox(height: 11),
          Text(
            strings.somAmount(basket),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 27,
              height: 1.15,
              letterSpacing: -0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.basketPrice,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// the two things you can do with a shop you have decided to visit, then the number itself. the
// address is not here - it is under the name.
//
// **the actions come before the number**, which is the reverse of how this block started: almost
// everybody taps «Позвонить», and the few who want the digits want them to copy, which is what the
// disc on the end of the row is for. the number is still not a control - a tappable number above a
// button that dials is two answers to one question.
class _Contacts extends StatelessWidget {
  const _Contacts({
    required this.shop,
    required this.strings,
    required this.onCall,
    required this.onRoute,
    required this.onCopyPhone,
  });

  final Shop shop;
  final AppLocalizations strings;
  final VoidCallback onCall;
  final VoidCallback onRoute;
  final VoidCallback onCopyPhone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 18, _gutter, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: strings.callButton,
                  icon: CupertinoIcons.phone_fill,
                  onTap: onCall,
                  isPrimary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: strings.routeButton,
                  icon: CupertinoIcons.location_north_line_fill,
                  onTap: onRoute,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PhoneTile(shop: shop, strings: strings, onCopy: onCopyPhone),
        ],
      ),
    );
  }
}

// the number, recessed into the white surface so it reads as a detail of the shop rather than
// another thing to press. page colour rather than `surfaceMuted`: at this size a 1% step off white
// is not a panel, it is a printing fault.
class _PhoneTile extends StatelessWidget {
  const _PhoneTile({required this.shop, required this.strings, required this.onCopy});

  final Shop shop;
  final AppLocalizations strings;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.surfaceWhite,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.store, color: AppColors.textMuted, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.phoneLabel,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                    height: 1.2,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shop.contactPhone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // positive letter spacing, where every other heading here is negative: a phone number is read in
                  // groups of digits, and tightening it makes one long number out of four short ones
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    height: 1.2,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: strings.copyPhoneTooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCopy,
                // the 44px accessibility floor, which is wider than the glyph needs
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(LucideIcons.copy, color: AppColors.textMuted, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// one filled, one outlined - they are not peers, since a phone number is why most of these cards are
// opened. the outlined one is white inside a trackGrey edge, the only outline visible on white.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final foreground = isPrimary ? Colors.white : AppColors.textDark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // the coloured glow is reserved for a primary action - see AppShadows.accent
        boxShadow: isPrimary ? AppShadows.accent(AppColors.primaryOrange) : null,
      ),
      child: Material(
        color: isPrimary ? AppColors.primaryOrange : AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: isPrimary ? null : Border.all(color: AppColors.trackGrey, width: 1.2),
            ),
            child: SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        letterSpacing: 0.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// the count is of everything priced, not of what the search left showing: it describes the shop, and
// a number falling to 3 while a filter was typed would read as the catalogue shrinking
class _ProductsHeading extends StatelessWidget {
  const _ProductsHeading({required this.count, required this.strings});

  final int count;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          strings.shopProductsSectionTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 17,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        // in a pill, so a loose number beside a heading is not read as part of it. trackGrey, not
        // `background`: this heading sits on the page itself, and a pill the page's own colour is
        // not there at all.
        if (count > 0) ...[
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.trackGrey,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// a shop with nothing priced gets a line saying so rather than a hidden section, which would read as
// "this app has no products area". a *search* that matched nothing gets a different line: it is the
// reader's query that is empty, not the shop.
class _ProductsSliver extends StatelessWidget {
  const _ProductsSliver({
    required this.products,
    required this.shopName,
    required this.strings,
    required this.isFirstLoad,
    required this.hasFailed,
    required this.isFiltered,
  });

  final List<Product> products;

  /// the tiles here carry no shop of their own, so a saved one is given this shop's name - that is
  /// what a favourite is shown with everywhere else
  final String shopName;

  final AppLocalizations strings;
  final bool isFirstLoad;
  final bool hasFailed;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFirstLoad) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 34),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryOrange),
            ),
          ),
        ),
      );
    }

    if (products.isEmpty) {
      final message = switch ((hasFailed, isFiltered)) {
        // the failure wins over the filter: telling the reader to try another word would send them typing at
        // a screen with no data behind it
        (true, _) => strings.productsLoadError,
        (false, true) => strings.searchNoResults,
        (false, false) => strings.noPricedProductsYet,
      };

      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    final favorites = context.watch<FavoritesController>();

    // a sliver grid, so a hundred-product catalogue builds one screenful of tiles - see the note at the
    // top of this file
    void save(Product product) =>
        toggleFavorite(context, CategoryProduct(product: product, shopName: shopName));

    return ProductSliverGrid(
      tiles: [
        for (final product in products)
          ProductTile(
            product: product,
            strings: strings,
            showBuyerActions: true,
            isFavorite: favorites.contains(product.id),
            onFavoriteToggle: () => save(product),
          ),
      ],
    );
  }
}
