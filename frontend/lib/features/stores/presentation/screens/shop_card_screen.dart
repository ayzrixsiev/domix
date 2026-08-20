import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/products/data/product_model.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/widgets/shop_category_banner.dart';

/// One shop, in full: whose card this is, what their basket costs, how to reach them, and what they
/// sell.
///
/// **There is one of these and every route into a shop ends here** - a pin on the map, a card in the
/// VIP carousel, a row in Лучшие предложения. Before this screen existed only the map could open a
/// shop, as a modal sheet built inside `map_screen.dart`, so the same object was a destination from
/// one place in the app and unreachable from three others: tapping a VIP card the founder had been
/// paid to place did nothing at all.
///
/// ## It is one screen with two chromes, and that split is the whole design
///
/// The *content* is identical everywhere - the same cover, the same three cards, the same catalogue.
/// What differs is how it arrives:
///
///  * **From the map it is a draggable sheet** ([showShopCardSheet]) sitting over the map rather than
///    replacing it, and a downward drag puts it away. That is the gesture anyone who has used a phone
///    maps app already has in their thumb, and it is what fixes the cost this screen was shipped
///    with: a pushed route meant comparing three nearby shops was three pushes and three pops, each
///    one throwing the map away and rebuilding it.
///  * **From anywhere else it is a full-screen route** ([ShopCardScreen]). A list opening a modal
///    sheet on top of itself is not a pattern this app uses anywhere, and there is no map underneath
///    worth keeping in view - the home feed is exactly where the reader just was.
///
/// Both are a [CustomScrollView], which is what makes the product catalogue a **sliver**. The old
/// sheet's grid was `shrinkWrap: true`, which lays out every child to measure itself - a hundred
/// tiles mounted at once, each firing an `Image.network` the moment it mounts. That is the bug in
/// CLAUDE.md §8 whose symptom is not slow images but a *failed price save*.
class ShopCardScreen extends StatelessWidget {
  const ShopCardScreen({super.key, required this.shop});

  /// The whole shop, never an id to look up.
  ///
  /// Everything on this screen except the catalogue is already in hand at every entry point: the map
  /// holds the list it drew its pins from, and `GET /api/home` sends full shop rows that
  /// `HomeShopPreview` simply projects down for the feed. So the card paints complete on its first
  /// frame, with no spinner and no second round trip for facts the app already had.
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    // there is no AppBar on this screen any more - the cover runs to the top of the content and the
    // back button floats over it - so the status bar's icons have to be asked for explicitly rather
    // than inherited from an AppBar that is no longer there.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: ShopCardView(shop: shop, chrome: ShopCardChrome.route),
        ),
      ),
    );
  }
}

/// Opens the shop card as the map's draggable sheet.
///
/// **The numbers are the behaviour**, so they are worth reading rather than skipping:
///
///  * `initialChildSize`/`maxChildSize` 0.92 - "most of the screen, not all of it". The strip of map
///    left showing above it is what says the map is still there and is still where Back goes; a
///    sheet at 1.0 is a full-screen route wearing rounded corners.
///  * `minChildSize` 0.5 with `shouldCloseOnMinExtent` (the default) - dragging the sheet down to
///    half its height dismisses it. That is what "drop it like in an iPhone app" is: there is no
///    close button anywhere on this sheet, and there does not need to be one.
///  * `snap` - released anywhere between the two, it goes to whichever is nearer. Without it a sheet
///    left at 70% simply stays at 70%, which reads as a control that did not finish moving.
///
/// The `ScrollController` handed to the builder is the link between the two gestures: it is attached
/// to the card's own `CustomScrollView`, so a drag that starts while the catalogue is scrolled down
/// scrolls, and the same drag once it is back at the top moves the sheet. Wiring anything else to
/// that controller - or forgetting to wire this - is how a sheet ends up only draggable by its
/// grabber.
Future<void> showShopCardSheet(BuildContext context, Shop shop) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // the sheet paints its own surface, corners and all, inside the draggable child - so the route's
    // own background has to be out of the way or it would draw a second square-cornered one behind
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      snap: true,
      // false, because the modal route sizes itself to this child. `true` would make it fill the
      // whole viewport with a transparent slab above the sheet, which would swallow every tap meant
      // for the barrier - so the map would stop being dismissable by tapping it.
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

  /// The sheet's own controller, which must end up on the scroll view - it is what lets a drag hand
  /// itself from the list to the sheet. Null in the pushed route, where the scroll view owns its
  /// own position.
  final ScrollController? scrollController;

  @override
  State<ShopCardView> createState() => _ShopCardViewState();
}

class _ShopCardViewState extends State<ShopCardView> {
  /// The catalogue filter. Held here rather than in the sliver so the products heading, the field
  /// and the grid all read one value.
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Below this many priced products the search field is not drawn at all.
  ///
  /// The grid is two per row, so eight products is four rows - about one screenful, and the point at
  /// which scrolling stops being the obvious way to find something. A shop with three priced items
  /// does not need a search box; it needs the three items, and a field over them would be a control
  /// that filters a list already entirely on screen.
  static const int _searchThreshold = 8;

  bool get _isSheet => widget.chrome == ShopCardChrome.sheet;

  @override
  void initState() {
    super.initState();
    // deferred past the first frame: loadProducts sets its busy flag and notifies *before* its first
    // await, and notifying while this element is still being mounted is flutter's "setState() called
    // during build". the same reason MapScreen and MessagesScreen defer theirs.
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

  /// Pull-to-refresh re-reads the catalogue, which is the only thing on this screen that changes
  /// while it is open - an owner pricing products in another session, most obviously.
  Future<void> _refresh() {
    return context.read<ProductsController>().loadProducts(widget.shop.id, force: true);
  }

  Future<void> _dial() async {
    if (!await _tryOpen(Uri.parse('tel:${widget.shop.contactPhone}'))) _reportNothingToOpenWith();
  }

  /// Hands the shop's coordinates to **whatever maps app the phone actually has**, and only falls
  /// back to a web map when there is none.
  ///
  /// `geo:` is an Android platform scheme, not one app's: every maps app on the phone registers for
  /// it, so the system shows a chooser - Yandex, Google, 2GIS, whatever is installed - and the user's
  /// own default wins. It costs nothing, needs no package and no api key. The previous version went
  /// straight to a `https://yandex.uz/maps/` url, which opens Yandex Maps *if it is installed* and a
  /// browser otherwise, so a phone with Google Maps and no Yandex got a web page.
  ///
  /// **What the fallback buys, and what `geo:` costs.** `geo:` can express "here is a point" and
  /// cannot express "route to it from where I am" - there is no route form of the scheme, and the
  /// per-app ones (`google.navigation:`, `yandexmaps://`) are each a single app again. So the geo
  /// link drops the pin and the maps app's own «Маршрут» button is one tap away, while the web url
  /// kept underneath still asks for the route outright. Trying the platform scheme first and the url
  /// second is what makes both true: the common case opens the app the user already uses, and a
  /// phone with no maps app at all still gets an answer.
  ///
  /// Both need a `<queries>` entry in AndroidManifest.xml, `geo` beside the `https` one - Android 11
  /// package visibility is why (CLAUDE.md §8).
  Future<void> _route() async {
    final shop = widget.shop;
    final point = '${shop.latitude},${shop.longitude}';
    // parentheses delimit the label in a geo: uri, so a shop with one in its name would truncate its
    // own pin caption. Uri.encodeComponent deliberately leaves them alone, hence the strip.
    final label = Uri.encodeComponent(shop.name.replaceAll(RegExp(r'[()]'), ''));

    if (await _tryOpen(Uri.parse('geo:$point?q=$point($label)'))) return;
    if (await _tryOpen(Uri.parse('https://yandex.uz/maps/?rtext=~$point&rtt=auto'))) return;
    _reportNothingToOpenWith();
  }

  /// **The return value of `launchUrl` is the signal, not `canLaunchUrl`.** Android 11 package
  /// visibility makes `canLaunchUrl` answer false for perfectly launchable links unless every scheme
  /// is declared, which is how the login flow once reported "Telegram is not installed" on a phone
  /// with Telegram open - see CLAUDE.md §8. It also throws rather than returning false when nothing
  /// claims the scheme, which is why the catch is part of the answer and not just logging.
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
    final strings = Provider.of<LanguageProvider>(context, listen: false).strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.couldNotOpenExternalApp),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  /// The catalogue as the customer sees it: **priced rows only**.
  ///
  /// An unpriced row is useful to the *owner*, which is why their own grid shows it, but to a
  /// customer it is a tile that answers no question - and on a fresh shop there would be a hundred of
  /// them burying the handful that are priced.
  List<Product> _pricedProducts(ProductsController controller) => [
        for (final product in controller.productsFor(widget.shop.id))
          if (product.hasPrice) product,
      ];

  /// Matched on the name and nothing else. A shop's catalogue is one shop's products, so the seller
  /// is not a thing to search by, and the unit ("шт") would match most of the list. `contains`
  /// rather than a prefix match for the same reason the server's search uses a leading wildcard:
  /// people type «мешок» to find «Цемент в мешках».
  List<Product> _matching(List<Product> priced) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return priced;
    return [
      for (final product in priced)
        if (product.name.toLowerCase().contains(query)) product,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<ProductsController>(context);
    final shop = widget.shop;

    final priced = _pricedProducts(controller);
    final matches = _matching(priced);
    final isFirstLoad = controller.isLoadingFor(shop.id) && !controller.hasLoaded(shop.id);

    // the page gutter. 16, not the 20 the app's form screens use: the cover is the widest object on
    // the screen and wants the edges.
    const gutter = EdgeInsets.symmetric(horizontal: 16);

    final scrollView = CustomScrollView(
      controller: widget.scrollController,
      // onDrag, because this screen has a text field in the middle of it. dragging the catalogue is
      // the gesture nearest to hand once the keyboard is up, and on the sheet it is the same drag
      // that would otherwise be putting the sheet away with the keyboard still on top of it.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, _isSheet ? 4 : 8, 16, 0),
          sliver: SliverToBoxAdapter(child: _Hero(shop: shop, strings: strings)),
        ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 12)),
          sliver: SliverToBoxAdapter(child: _BasketPriceCard(shop: shop, strings: strings)),
        ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 12)),
          sliver: SliverToBoxAdapter(
            child: _ContactsCard(
              shop: shop,
              strings: strings,
              onCall: _dial,
              onRoute: _route,
            ),
          ),
        ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 26)),
          sliver: SliverToBoxAdapter(
            child: _ProductsHeading(count: priced.length, strings: strings),
          ),
        ),
        if (priced.length >= _searchThreshold)
          SliverPadding(
            padding: gutter.add(const EdgeInsets.only(top: 12)),
            sliver: SliverToBoxAdapter(
              child: _CatalogueSearchField(
                controller: _search,
                strings: strings,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 12)),
          sliver: _ProductsSliver(
            products: matches,
            strings: strings,
            isFirstLoad: isFirstLoad,
            // three different empty states, and telling them apart is the point: the request failed,
            // the shop has priced nothing, or this particular search matched nothing.
            hasFailed: controller.loadErrorFor(shop.id) != null,
            isFiltered: _query.trim().isNotEmpty,
          ),
        ),
        // a tail so the last row of tiles is not flush against the bottom of the screen, plus
        // whatever the gesture bar takes. both chromes are drawn over the shell, so the floating nav
        // bar is not in the way - only the system inset is.
        //
        // **`viewInsets` is in there for the sheet, and it is not padding for its own sake.** The
        // sheet's Scaffold does not resize for the keyboard (it cannot - the draggable sheet owns its
        // height), so the bottom of the list stays underneath it, and the catalogue search field sits
        // low enough on a short shop to be one of the things covered. Adding the keyboard's height to
        // the scrollable extent is what gives `ensureVisible` somewhere to scroll the focused field
        // *to*. It is zero in the pushed route, where the Scaffold resizes the body itself and the
        // inset never reaches this far down the tree.
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
      // **no RefreshIndicator on the sheet.** A pull at the top of the list is the gesture that puts
      // the sheet away, and a spinner competing for it would mean the sheet sometimes refreshes and
      // sometimes closes depending on how far the thumb travelled - which is the worst possible
      // answer. The route keeps it: there is nothing else that gesture could mean there.
      ShopCardChrome.route => Stack(
          children: [
            RefreshIndicator(
              color: AppColors.primaryOrange,
              onRefresh: _refresh,
              child: scrollView,
            ),
            // inside the cover's own left edge (the 16 gutter) rather than straddling it
            const Positioned(top: 16, left: 26, child: _BackButton()),
          ],
        ),
      ShopCardChrome.sheet => _SheetSurface(child: scrollView),
    };
  }
}

/// The sheet's own surface: rounded top, the page's background colour, and a grabber.
///
/// **The `Scaffold` is not decoration.** A modal bottom sheet is a route with no Scaffold of its
/// own, so `ScaffoldMessenger.of(context).showSnackBar` from inside it lands in the *map's* Scaffold
/// - underneath the sheet, where nobody will ever see it. Registering one here puts the "nothing on
/// this phone can open that" message inside the sheet, which is the only place it is any use.
/// `resizeToAvoidBottomInset` is off because the draggable sheet already owns its own height, and
/// two things resizing for one keyboard fight.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  final Widget child;

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
        child: Column(
          children: [
            const _SheetGrabber(),
            // the scroll view, and it must be the *only* scrollable the sheet's controller reaches -
            // that is what hands a drag between the list and the sheet
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// The handle: the one piece of chrome that says this thing can be dragged.
///
/// It is not a button and does nothing when tapped, on purpose - a grabber that also closed the
/// sheet would be a 38px close target sitting where a thumb rests to drag.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.trackGrey,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// The pushed route's way back, floating over the cover rather than sitting in an app bar.
///
/// A white circle with a shadow, because it has to stay legible against two very different things:
/// the dark cover at the top of the scroll, and the grey page once the reader has scrolled past it.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).maybePop(),
        child: Ink(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            shape: BoxShape.circle,
            boxShadow: AppShadows.floating,
          ),
          child: const Icon(CupertinoIcons.back, color: AppColors.textDark, size: 20),
        ),
      ),
    );
  }
}

/// The cover and the identity block, as one object - because the second overlaps the first.
///
/// **The overlap is a `Stack` sized by its unpositioned child**, not a negative margin (illegal) or
/// a `Transform` (which would leave a hole in the layout the size of the shift). The banner is
/// positioned at the top and the identity card is laid out at `bannerHeight - overlap`, so the stack
/// measures exactly as tall as the two of them minus the bite - which is what a parent sliver needs
/// in order to know how much room to give it.
class _Hero extends StatelessWidget {
  const _Hero({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  /// how far the identity card climbs onto the picture
  static const double _overlap = 26;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ShopCategoryBanner(
            category: shop.category,
            name: shop.name,
            isVip: shop.isVip,
            // clear of the card below by 12, or a two-line name spends its second line behind it
            contentInset: _overlap + 12,
          ),
        ),
        Padding(
          // inset from the cover's own edges, so the card reads as sitting *on* the picture rather
          // than as the next full-width band under it
          padding: const EdgeInsets.only(
            top: ShopCategoryBanner.defaultHeight - _overlap,
            left: 10,
            right: 10,
          ),
          child: _IdentityCard(shop: shop, strings: strings),
        ),
      ],
    );
  }
}

/// What kind of shop this is and where it is. Two lines, and deliberately nothing else.
///
/// **No chips and no pills anywhere in it.** This block was a row of them - a category chip, a
/// rating chip, a VIP pill - and a card that opens with four small rounded boxes reads as a filter
/// bar rather than as an identity. The hierarchy carries it instead: the category is set as a
/// heading and the address as a caption under it, which is the same shape as every address on every
/// listing anyone has ever read. The placement mark moved onto the cover, where there is a picture
/// to sit on.
///
/// The category glyph is **the pin's own** ([ShopCategory.icon]) and the words beside it are what
/// that glyph meant. Someone arriving here from the map has just tapped a teardrop with a wrench in
/// it; this is the only place in the app that translates it.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        // `raised`, not `card`: this one is half on top of a dark picture, and the barely-there
        // shadow disappears entirely against it
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(shop.category.icon, color: AppColors.textMuted, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  shop.category.label(strings),
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
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, left: 2),
                child: Icon(CupertinoIcons.location_solid, color: AppColors.textFaint, size: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shop.address,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13.5,
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

/// How this shop compares to its market, and then what the shared basket costs here.
///
/// **The comparison is first and the number is second**, which is the reverse of a price tag and is
/// the point of the whole product: "на 4% дешевле рынка" is the fact a customer came for, and
/// "4 850 000 сум" is what it is 4% of. A reader who stops after one line has still read the useful
/// one.
///
/// The two facts are drawn from one condition rather than one each: a shop is in the index only with
/// its whole template priced, so `basketPrice` and `priceTier` are both present or both absent, and
/// branching on them separately would be writing code for a state the database cannot produce.
///
/// **The empty case is a sentence, not a blank.** One unpriced row keeps a shop out, so this is the
/// common case early on - and a customer who tapped a pin and found nothing where a price should be
/// reads that as the app failing, where a line about the shop's own prices reads as the shop's state.
class _BasketPriceCard extends StatelessWidget {
  const _BasketPriceCard({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final basket = shop.basketPrice;
    final tier = shop.priceTier;

    if (basket == null || tier == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(CupertinoIcons.clock, color: AppColors.textFaint, size: 14),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                strings.basketPriceIncomplete,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the full sentence rather than the compact form: this is where someone who tapped a pin
          // reading "−4%" finds out what those four characters meant
          Align(
            alignment: Alignment.centerLeft,
            child: PriceTierBadge(
              tier: tier,
              differencePercent: shop.priceDifferencePercent,
              strings: strings,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            strings.basketPrice,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.5,
              height: 1.2,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            strings.somAmount(basket),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 26,
              height: 1.15,
              letterSpacing: -0.7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The phone number, and the two things you can do with a shop you have decided to visit.
///
/// **The address is not here any more.** It is two cards up, under the category, where the card
/// introduces itself - and printing it twice on one screen made the contacts block look like a form
/// nobody had finished filling in. What is left is exactly what a contacts block is for: a number to
/// call and a way to get there.
///
/// The number is drawn large and is not a control. The call button directly under it is the control,
/// and a tappable number six points above a button that does the identical thing is two answers to
/// one question - the kind of duplicate affordance people press twice and then report as broken.
class _ContactsCard extends StatelessWidget {
  const _ContactsCard({
    required this.shop,
    required this.strings,
    required this.onCall,
    required this.onRoute,
  });

  final Shop shop;
  final AppLocalizations strings;
  final VoidCallback onCall;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.shopContactsTitle,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.5,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(CupertinoIcons.phone_fill, color: AppColors.textMuted, size: 16),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  shop.contactPhone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 19,
                    height: 1.2,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }
}

// the two things somebody who opened a shop wants to do. one filled, one outlined: they are not
// peers - a phone number is the reason most of these cards are opened at all.
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
        // the coloured glow is the one place brand orange bleeds outside its own shape, and it is
        // reserved for a primary action - see AppShadows.accent
        boxShadow: isPrimary ? AppShadows.accent(AppColors.primaryOrange) : null,
      ),
      child: Material(
        color: isPrimary ? AppColors.primaryOrange : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: isPrimary ? null : Border.all(color: AppColors.hairline),
            ),
            child: SizedBox(
              height: 50,
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

// "Товары" plus how many, matching the section headings on the home feed. the count is of everything
// priced, not of what the search left showing - it describes the shop, and a number that fell to 3
// while a filter was typed would read as the catalogue shrinking.
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
        if (count > 0) ...[
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Filters the catalogue that is already on the phone.
///
/// **It searches in memory and sends nothing.** The whole catalogue arrived in the one request this
/// screen makes - at most a template plus thirty rows - so a keystroke costs a `contains` over a
/// list, not a round trip. That is the difference between this field and the home feed's, which is a
/// button that opens a screen precisely because *its* search is a sequential scan on the server
/// (CLAUDE.md §7): the argument against as-you-type there does not exist here.
///
/// The well is `trackGrey` with no border, the same recipe the home feed's search bar now wears - so
/// the two read as the same control even though one is a field and one is a button.
class _CatalogueSearchField extends StatelessWidget {
  const _CatalogueSearchField({
    required this.controller,
    required this.strings,
    required this.onChanged,
  });

  final TextEditingController controller;
  final AppLocalizations strings;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.trackGrey,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.primaryOrange,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: strings.shopProductsSearchHint,
                hintStyle: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          // rebuilt off the field itself rather than from the parent's state, so clearing does not
          // cost a rebuild of the whole card - the same reason the unit chips on the product form
          // listen to their controller
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.clear();
                  onChanged('');
                  // clearing is usually the last thing anyone wants from the field, so it takes the
                  // keyboard with it rather than leaving it up over the results it just restored
                  FocusScope.of(context).unfocus();
                },
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(CupertinoIcons.clear_circled_solid,
                      color: AppColors.textGrey, size: 17),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The catalogue, as a sliver.
///
/// A shop with nothing priced gets a line saying so rather than a hidden section: a missing section
/// reads as "this app has no products area", which is a different and wrong message. A *search* that
/// matched nothing gets a different line again - it is the reader's query that is empty, not the
/// shop.
class _ProductsSliver extends StatelessWidget {
  const _ProductsSliver({
    required this.products,
    required this.strings,
    required this.isFirstLoad,
    required this.hasFailed,
    required this.isFiltered,
  });

  final List<Product> products;
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
        // the failure wins over the filter: a search that found nothing because the catalogue never
        // arrived is not a search result, and telling the reader to try another word would send them
        // typing at a screen that has no data behind it
        (true, _) => strings.productsLoadError,
        (false, true) => strings.searchNoResults,
        (false, false) => strings.noPricedProductsYet,
      };

      return SliverToBoxAdapter(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    // a sliver grid, so a hundred-product catalogue builds one screenful of tiles and fires one
    // screenful of image requests - see the class comment on ShopCardScreen
    return ProductSliverGrid(
      tiles: [
        for (final Product product in products)
          ProductTile(product: product, strings: strings),
      ],
    );
  }
}
