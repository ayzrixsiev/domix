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
import 'package:frontend/features/stores/data/price_tier.dart';
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
/// The *content* is identical everywhere - the same cover, the same details, the same catalogue.
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
///
/// ## How it is laid out, and what changed on 2026-08-20
///
/// It used to be a cover inset inside the page gutter, with an identity card lapped over it and two
/// more rounded white cards under that, all floating on the grey page. Three things were wrong with
/// it and all three came from the same habit - **using a box to say "a new section starts here"**:
///
///  * A card is a heavy separator. Three of them stacked, each with its own radius and shadow, made
///    a page about one shop look like a list of three unrelated things.
///  * The cover could not be a *picture*. Boxed inside a 16px gutter with its own rounded corners,
///    it read as an illustration pasted into the layout rather than as the top of the screen.
///  * The map's sheet already has rounded corners of its own, so a rounded cover inside them was
///    two radii a few pixels apart.
///
/// So: the cover is **full-bleed and runs to the very top**, the details below it sit on one plain
/// white surface, and the sections inside that surface are separated by **hairline rules inset from
/// both edges** - a line that stops short of the screen is what a rule is, and it is the lightest
/// separator that still separates. The catalogue keeps the grey page under it, which is what marks
/// the one real break on the screen: everything above is *this shop*, everything below is *its
/// goods*.
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
    // **No `SafeArea` at the top, and that is the point of the cover.** The picture runs underneath
    // the status bar, so the clock and the battery sit on it - which is why the cover's own top is
    // painted near-white and why the overlay style is asked for explicitly here rather than
    // inherited from an AppBar this screen does not have. `dark` means *dark glyphs*, for a light
    // background.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: ShopCardView(shop: shop, chrome: ShopCardChrome.route),
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

/// The one horizontal inset on the screen. Text, rules, the search field and the product grid all
/// sit on it, so a rule ends exactly where a line of text does.
const double _gutter = 16;

class _ShopCardViewState extends State<ShopCardView> {
  /// The catalogue filter. Held here rather than in the sliver so the products heading, the field
  /// and the grid all read one value.
  final TextEditingController _search = TextEditingController();

  /// **Owned here rather than inside the field, because the field's own `TextField` is not the whole
  /// control.** Tapping the magnifier or the padding beside it has to focus the input too - see
  /// [_CatalogueSearchField], which is where the bug that made this necessary is written down.
  final FocusNode _searchFocus = FocusNode();

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
    _searchFocus.dispose();
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

    // the pushed route draws its cover *under* the status bar, so the picture has to be that much
    // taller for the same 240 of it to be visible below the clock. the sheet is opened with
    // `useSafeArea`, so its own top edge is already clear of it and the height is the plain one.
    final coverHeight = ShopCategoryBanner.defaultHeight +
        (_isSheet ? 0 : MediaQuery.paddingOf(context).top);

    const gutter = EdgeInsets.symmetric(horizontal: _gutter);

    final scrollView = CustomScrollView(
      controller: widget.scrollController,
      // onDrag, because this screen has a text field in the middle of it. dragging the catalogue is
      // the gesture nearest to hand once the keyboard is up, and on the sheet it is the same drag
      // that would otherwise be putting the sheet away with the keyboard still on top of it.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        // no padding of any kind around the cover: full width, hard against the top. on the sheet
        // the surface's own Clip.antiAlias is what rounds its two upper corners.
        SliverToBoxAdapter(
          child: ShopCategoryBanner(category: shop.category, height: coverHeight),
        ),
        SliverToBoxAdapter(
          child: _DetailsSurface(
            shop: shop,
            strings: strings,
            onCall: _dial,
            onRoute: _route,
          ),
        ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 24)),
          sliver: SliverToBoxAdapter(
            child: _ProductsHeading(count: priced.length, strings: strings),
          ),
        ),
        if (priced.length >= _searchThreshold)
          SliverPadding(
            padding: gutter.add(const EdgeInsets.only(top: 14)),
            sliver: SliverToBoxAdapter(
              child: _CatalogueSearchField(
                controller: _search,
                focusNode: _searchFocus,
                strings: strings,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
        SliverPadding(
          padding: gutter.add(const EdgeInsets.only(top: 14)),
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
            // clear of the status bar the cover now runs under
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 14,
              child: const _BackButton(),
            ),
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
///
/// **The grabber floats over the content instead of sitting above it**, which is what lets the cover
/// reach the sheet's own top edge and be cropped by its corners. It was a row in a `Column` above
/// the scroll view, and the strip of page it occupied was the one thing stopping the picture from
/// starting where the sheet does. `IgnorePointer` is what keeps the change free: a drag that lands
/// on the handle falls through to the scroll view underneath, which is the thing the sheet listens
/// to, so the handle stays draggable without being a gesture target of its own.
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
        child: Stack(
          children: [
            // the scroll view, and it must be the *only* scrollable the sheet's controller reaches -
            // that is what hands a drag between the list and the sheet
            Positioned.fill(child: child),
            const Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(child: Center(child: _SheetGrabber())),
            ),
          ],
        ),
      ),
    );
  }
}

/// The handle: the one piece of chrome that says this thing can be dragged.
///
/// Translucent black rather than [AppColors.trackGrey], because it now lies on the cover instead of
/// on the page - and the cover's top is near-white, where a pale grey handle is not there at all.
/// An ink of the background lets it darken whatever it happens to be over.
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

/// The pushed route's way back, floating over the cover rather than sitting in an app bar.
///
/// A white circle with a shadow **and a hairline ring**. The ring is new and it is not trim: the
/// cover is white-and-orange now, and its top-left corner - which is exactly where this sits - is
/// the whitest part of it, so a white disc with only a soft shadow under it had nothing to make it a
/// shape. The ring also has to survive the reader scrolling the cover away, which puts the same
/// button over the grey page.
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
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.trackGrey),
            boxShadow: AppShadows.floating,
          ),
          child: const Icon(CupertinoIcons.back, color: AppColors.textDark, size: 20),
        ),
      ),
    );
  }
}

/// Everything the card says about the shop itself, on **one white surface**.
///
/// Three white cards used to do this job, one per section, each rounded and shadowed and floating in
/// the page gutter. What they bought was separation; what they cost was the impression that a card
/// about one business is three things. A single surface with rules through it says the same and says
/// it more quietly - and it is what lets the cover above sit flush against it instead of leaving a
/// strip of grey page between a picture and the name of the thing in it.
///
/// **The price section is skipped entirely when there is no basket**, rules and all. A shop is in
/// the index only once its whole template is priced, so this is common early on, and what used to be
/// here was a sentence explaining that the shop had not finished pricing. It is gone: a customer is
/// not the audience for another business's unfinished admin, and reading one on the screen you
/// opened to compare prices is worse than reading nothing. What is left is a card that simply makes
/// no claim about this shop's prices, which is exactly the true statement.
class _DetailsSurface extends StatelessWidget {
  const _DetailsSurface({
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
    final basket = shop.basketPrice;
    final tier = shop.priceTier;

    return Container(
      width: double.infinity,
      color: AppColors.surfaceWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Identity(shop: shop, strings: strings),
          // the two facts are drawn from one condition rather than one each: a shop is in the index
          // only with its whole template priced, so basketPrice and priceTier are both present or
          // both absent, and branching on them separately would be writing code for a state the
          // database cannot produce.
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
          ),
        ],
      ),
    );
  }
}

/// The separator, and the only one on this screen.
///
/// **Inset from both edges**, so it reads as a rule under a block of text rather than as the seam
/// between two panels - a line that runs wall to wall cuts the surface in half, which is the thing
/// the white cards were doing and the reason they went.
///
/// [AppColors.trackGrey] rather than `hairline`: `hairline` is the border token for a white card
/// standing on the *grey* page, where a shadow is doing most of the separating anyway. On white with
/// nothing else helping, it is about a 1.08:1 step and simply does not appear.
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

/// Whose card this is: the kind of shop, its name, where it is.
///
/// **The name is here rather than on the cover.** It was laid over the picture while the picture was
/// a dark gradient; a white-and-orange cover has nowhere on it that white text is safe and nowhere
/// that dark text is either, and a scrim added to make one work would be a grey band over a cover
/// that was just redesigned to be clean. Below it the name is a heading, which is what it is.
///
/// **The category is an eyebrow above the name, not a chip and not a row with the glyph in it.** The
/// glyph is already on the cover, forty pixels up, inside the white disc - printing it again under
/// its own picture is the same mark twice. Small caps over a large name is the shape a listing has
/// had since before there were phones, and it costs no colour and no box.
class _Identity extends StatelessWidget {
  const _Identity({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 20, _gutter, 18),
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
              // the placement mark. it was on the cover in white; here it is a star and three
              // letters in brand orange - a highlight, which is one of the things orange is for,
              // and small enough not to compete with the name under it. **Not a capsule**: a pill
              // beside an eyebrow is a chip, and a chip is what this block was rebuilt to be rid of.
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
          const SizedBox(height: 7),
          Text(
            shop.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              height: 1.16,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
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

/// How this shop compares to its market, and then what the shared basket costs here.
///
/// **The comparison is first and the number is second**, which is the reverse of a price tag and is
/// the point of the whole product: «на 4% дешевле рынка» is the fact a customer came for, and
/// «4 850 000 сум» is what it is 4% of. A reader who stops after one line has still read the useful
/// one.
///
/// Three lines, no box and no tint behind them. The comparison is the badge at
/// [PriceTierBadgeSize.headline] - the same widget the pin and the feed use, so the wording and the
/// three colours stay in one file - then the amount at the largest size on the screen, then the
/// caption naming what the amount is. **The caption is under the number rather than over it**: the
/// number is the thing the eye should land on, and a label above it takes that position for a word
/// nobody is looking for.
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
          // the full sentence rather than the compact form: this is where someone who tapped a pin
          // reading "−4%" finds out what those four characters meant
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

/// The phone number, and the two things you can do with a shop you have decided to visit.
///
/// **The address is not here.** It is in the identity block, under the name, where the card
/// introduces itself - and printing it twice on one screen made this block look like a form nobody
/// had finished filling in.
///
/// It read as an odd block for two more reasons, both now gone. It carried a section title
/// («Контакты») *and* a field caption *and* a glyph beside the number, so three different kinds of
/// label were stacked over one fact; the rule above it now does the section's job, leaving one
/// caption naming one value. And its secondary button was filled [AppColors.surfaceMuted] with a
/// `hairline` border - a fill and an edge that are both within about 3% of white, which on this
/// surface is a button-shaped area of nothing.
///
/// The number is drawn large and is **not** a control. The call button directly under it is the
/// control, and a tappable number six points above a button that does the identical thing is two
/// answers to one question - the kind of duplicate affordance people press twice and then report as
/// broken.
class _Contacts extends StatelessWidget {
  const _Contacts({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 18, _gutter, 22),
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
          const SizedBox(height: 5),
          Text(
            shop.contactPhone,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // a *positive* letter spacing, where every other heading on this screen is negative: a
            // phone number is read in groups of digits rather than as a word, and tightening it is
            // what makes one long number out of four short ones.
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              height: 1.2,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
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
//
// the outlined one is white inside a `trackGrey` edge, which is the only outline that is actually
// visible on a white surface. it was a surfaceMuted fill inside a hairline, and both of those are
// within 3% of the surface they were drawn on.
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
/// **The whole well is the tap target, and that is a bug fix rather than a refinement.** A
/// `TextField` only takes focus where the `TextField` is, and this one is the `Expanded` in the
/// middle of a row - so the 14px of padding, the 19px magnifier and the 10px after it were about
/// 43px of dead surface at the left end of a control that looks exactly like a button. Pressing the
/// magnifier and having nothing happen is the whole of "the search button does not work". The outer
/// `GestureDetector` hands focus to the field; a tap that lands *on* the field still resolves to the
/// field's own recogniser, since the innermost one in the arena wins.
///
/// The well is [AppColors.trackGrey] with no border and no shadow - the home feed's search bar
/// exactly, hint colour and heights included, so the two read as one control across two screens.
class _CatalogueSearchField extends StatelessWidget {
  const _CatalogueSearchField({
    required this.controller,
    required this.focusNode,
    required this.strings,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AppLocalizations strings;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.trackGrey,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
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
///
/// The line is set plainly on the page rather than inside a bordered box. It is one sentence in the
/// place a grid would be, and the grid it replaces has no frame either.
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
