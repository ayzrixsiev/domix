import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/price_tier_badge.dart';
import 'package:frontend/features/products/presentation/controllers/products_controller.dart';
import 'package:frontend/features/products/presentation/widgets/product_grid.dart';
import 'package:frontend/features/products/presentation/widgets/product_tile.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import '../widgets/domix_map.dart';
import '../widgets/map_search_panel.dart';
import '../widgets/shop_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.isActive = true,
  });

  final bool showScaffold;
  final double bottomPadding;

  /// Whether this screen is the tab the user is currently looking at.
  ///
  /// **The shell's `IndexedStack` builds every tab and paints one**, so `build()` running is not a
  /// signal that anybody can see this - and `initState` runs exactly once for the life of the app.
  /// That is why the shop list used to be fetched once and then never again: a failed load left
  /// «Не удалось загрузить магазины» sitting there with no way to retry, surviving even a restart
  /// of the app, because a restart put a *fresh* failing fetch in the same place.
  ///
  /// The shell passes `index == mapIndex`, so this flips false→true every time the map tab is
  /// selected, which is the moment [_MapScreenState.didUpdateWidget] uses to re-sync a stale list.
  /// Defaults to true for a standalone `MapScreen` that owns the whole route.
  final bool isActive;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // tashkent, since that's where domix currently operates - a sensible default center
  static const _defaultLatitude = 41.2995;
  static const _defaultLongitude = 69.2401;

  /// close enough to read street names after jumping to a search result
  static const _focusedZoom = 16.0;

  /// the whole city fits on screen at this zoom, which is why the map opens here - and why it is
  /// also the zoom at which drawing every pin stops being useful
  static const _initialZoom = 12.0;

  /// Below this zoom the map draws no shop pins at all.
  ///
  /// **What this does and does not solve.** MapKit culls off-screen objects itself, natively, so
  /// panning around a country's worth of shops costs nothing per off-screen shop - that half is the
  /// SDK's and is not reimplemented here. What culling cannot help with is the case this constant
  /// exists for: zoomed out over a city, *every* shop is inside the viewport, so every one of them
  /// is laid out, rasterized and drawn. Each pin is a `CustomPaint`, an icon and a shadowed pill
  /// with text; seventy of those is real work, and the result is unreadable anyway - seventy
  /// teardrops overlapping across Tashkent.
  ///
  /// 13 and not 12, deliberately: at [_initialZoom] the map opens with the pins withheld and a line
  /// saying so, and one pinch brings them in. Opening with them already drawn would mean the
  /// threshold only ever fired on the way *out*, which is not the behaviour a map is expected to
  /// have. Search still reaches any shop from any zoom - `MapSearchPanel` matches in memory against
  /// the full list, and picking a result flies to [_focusedZoom], well past this line.
  static const _minShopZoom = 13.0;

  DomixMapController? _map;

  /// Whether the camera is currently close enough in to draw pins.
  ///
  /// Kept as a bool rather than as the zoom itself, and that is the point of the whole design:
  /// the camera listener fires on every frame of a pinch or a fling, so holding the zoom in state
  /// would rebuild the pin list sixty times a second. A bool changes twice per crossing - once
  /// on the way out, once on the way back - and [_onZoomChanged] rebuilds only when it flips.
  bool _shopsVisible = _initialZoom >= _minShopZoom;

  @override
  void initState() {
    super.initState();

    // the first sync. IndexedStack keeps this screen's State alive across tab switches, so this
    // runs exactly once per app session - every later re-sync comes through didUpdateWidget below.
    // it is deliberately not gated on isActive: the shell builds every tab at launch, so fetching
    // here means the pins are already in hand the first time anybody presses Карта.
    _syncShops();
  }

  /// Re-syncs when this becomes the visible tab.
  ///
  /// [StoresController.refreshStoresIfStale] decides whether that costs a request: a list fetched a
  /// few seconds ago is left alone, one that failed or has aged out is fetched again. Switching to
  /// the map after deleting an account therefore shows the map without the deleted shops, and
  /// switching back after a failed load retries by itself instead of leaving a dead error banner.
  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // only the false→true edge. `isActive == true` on its own fires on every rebuild while the tab
    // is open, which with a live camera listener is a lot of them.
    if (widget.isActive && !oldWidget.isActive) _syncShops();
  }

  /// Asks the controller to re-fetch if what it holds has gone stale, **on the next frame**.
  ///
  /// The deferral is not optional, and it is why this is a method rather than one line at each call
  /// site. `loadStores()` calls `notifyListeners()` before its first `await`, and both callers run
  /// inside the build phase - `initState` while this element is being mounted, `didUpdateWidget`
  /// while the shell is rebuilding it. Notifying there marks listeners dirty during a build that is
  /// already under way, which is flutter's "setState()/markNeedsBuild() called during build"
  /// assertion. `addPostFrameCallback` puts the call after the frame instead.
  void _syncShops() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StoresController>().refreshStoresIfStale();
    });
  }

  // glides the camera instead of teleporting. the hand-rolled AnimationController and pair of
  // tweens this used to need are gone: MapKit animates a camera move natively, so the whole thing
  // is one call. see DomixMapController.flyTo.
  void _flyTo(double latitude, double longitude, {double zoom = _focusedZoom}) {
    _map?.flyTo(latitude, longitude, zoom: zoom);
  }

  // fires on every camera frame, so it has to be cheap and it has to not call setState unless the
  // answer actually changed. MapKit reports programmatic moves through the same listener, which is
  // what makes flying to a search result bring the pins in on its own.
  void _onZoomChanged(double zoom) {
    final visible = zoom >= _minShopZoom;
    if (visible != _shopsVisible) {
      setState(() => _shopsVisible = visible);
    }
  }

  void _showShopDetails(BuildContext context, Shop shop) {
    final strings = Provider.of<LanguageProvider>(context, listen: false).strings;

    showModalBottomSheet(
      context: context,
      // the sheet paints its own rounded surface, so the framework's must not sit behind it
      backgroundColor: Colors.transparent,
      // lets the sheet size past the default ~50% cap. it's content-sized today, but this is what
      // will let it keep working once products/promotions are added to it.
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => _ShopDetailsSheet(shop: shop, strings: strings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<StoresController>(context);

    Widget? statusBanner;
    if (controller.isLoading && controller.stores.isEmpty) {
      statusBanner = _MapMessageBanner(message: strings.loadingShops, isBusy: true);
    } else if (controller.loadError != null && controller.stores.isEmpty) {
      // the retry is the whole point of this branch. the banner used to be a sentence and nothing
      // else, so a user who hit a failed load had no control on screen that could do anything about
      // it - and the automatic re-sync above only fires on a tab switch, which is not something
      // anyone should have to guess at.
      statusBanner = _MapMessageBanner(
        message: strings.mapLoadError,
        isError: true,
        actionLabel: strings.retryButtonShort,
        onAction: () => controller.loadStores(),
      );
    } else if (controller.stores.isEmpty) {
      statusBanner = _MapMessageBanner(message: strings.noShopsYet);
    } else if (!_shopsVisible) {
      // last, and only once there are shops: a map that is empty because it is zoomed out is a
      // different fact from one that is empty because the city has no shops, and saying the wrong
      // one is worse than saying nothing
      statusBanner = _MapMessageBanner(
        message: strings.zoomInForShops(controller.stores.length),
        icon: LucideIcons.zoom_in,
      );
    }

    final body = Stack(
      children: [
        // deliberately NOT inside a SafeArea. a map is a canvas: it should run edge to edge and let
        // the status bar and the dynamic island float over it, the same way apple maps does. wrapping
        // it in SafeArea (as this screen used to) padded the whole notch band away and left a dead
        // strip of background across the top. only the controls further down are inset.
        DomixMap(
          initialLatitude: _defaultLatitude,
          initialLongitude: _defaultLongitude,
          initialZoom: _initialZoom,
          onZoomChanged: _onZoomChanged,
          onControllerReady: (controller) => _map = controller,
          // tapping the map itself drops the keyboard and closes the search dropdown
          onMapTap: () => FocusScope.of(context).unfocus(),
          pins: [
            if (_shopsVisible)
              for (final shop in controller.stores)
                MapPin(
                  id: shop.id.toString(),
                  latitude: shop.latitude,
                  longitude: shop.longitude,
                  // everything that changes how this pin is drawn, and nothing that does not. the
                  // shop's name is absent on purpose - two shops of the same category with the same
                  // comparison draw the same pin, and sharing one cached raster between them is the
                  // point. see MapPin.visualKey.
                  visualKey:
                      '${shop.category.code}|${shop.priceTier?.name ?? '-'}'
                      '|${shop.priceDifferencePercent ?? 0}',
                  onTap: () => _showShopDetails(context, shop),
                  builder: () => ShopMarker(
                    // what the pin draws inside itself - универсальный, сантехника, древесные
                    // материалы or обои. always present, unlike the price label above: a shop's
                    // category is picked when it is created and never changes.
                    category: shop.category,
                    // omitted entirely for a shop that has not priced its whole catalogue,
                    // which is most of them early on - matches the details sheet below.
                    // `!= null` where this used to be `> 0`: the guard is the same guard, but it
                    // asks the model instead of inferring it from a sentinel value.
                    priceTier: shop.priceTier,
                    priceDifferencePercent: shop.priceDifferencePercent,
                  ),
                ),
          ],
        ),

        // the controls layer - *this* is what respects the notch, not the map behind it
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MapSearchPanel(
                    shops: controller.stores,
                    strings: strings,
                    onShopSelected: (shop) {
                      _flyTo(shop.latitude, shop.longitude);
                      _showShopDetails(context, shop);
                    },
                    onPlaceSelected: (place) => _flyTo(place.latitude, place.longitude),
                  ),
                  if (statusBanner != null) ...[
                    const SizedBox(height: 10),
                    statusBanner,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // the clock and battery now sit over light map tiles rather than over our own background, so
    // they have to be told to paint dark. AnnotatedRegion applies the style while this screen is
    // the one on top, and reverts when another takes over.
    final styledBody = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: body,
    );

    if (!widget.showScaffold) {
      return styledBody;
    }

    return Scaffold(backgroundColor: AppColors.background, body: styledBody);
  }
}

// There was a hand-rolled `_MapAttribution` pill here and it is **deleted**, not moved. It existed
// because OpenStreetMap's ODbL licence requires visible credit and flutter_map's own attribution
// widget was covered by the floating nav bar once the map went full-bleed. MapKit draws Yandex's
// logo and copyright itself, as part of the map surface and as a condition of the licence - so
// adding our own would be a second, wrong credit for data that is no longer OSM's. If a future
// provider needs credit again, it belongs above the nav bar, at `bottomPadding + 10`.

// ─────────────────────────────────────────────────────────────────────────────
// shop details sheet
//
// laid out as a stack of independent sections separated by hairlines rather than as one block of
// text, so sections planned for later (opening hours, promotions, more actions) drop in as
// additional entries without the layout needing to be rethought. the sheet already scrolls and is
// height-capped for the same reason - which is what let the product catalogue land at the bottom of
// it without touching anything above.
// ─────────────────────────────────────────────────────────────────────────────

class _ShopDetailsSheet extends StatelessWidget {
  const _ShopDetailsSheet({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetGrabber(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ShopBanner(imageUrl: shop.imageFullUrl),
              ),
              const SizedBox(height: 16),

              // identity: name carries all the emphasis, everything else steps down a level
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.2,
                        letterSpacing: -0.3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _ShopMetaLine(shop: shop, strings: strings),
                    const SizedBox(height: 14),
                    _BasketPriceBlock(shop: shop, strings: strings),
                  ],
                ),
              ),

              const SizedBox(height: 18),
              const _SheetDivider(),
              _DetailRow(
                icon: CupertinoIcons.location_solid,
                label: strings.addressLabel,
                value: shop.address,
              ),
              // indented to line up with the text column, the way grouped ios lists separate rows
              const _SheetDivider(indent: _DetailRow.textInset),
              _DetailRow(
                icon: CupertinoIcons.phone_fill,
                label: strings.phoneLabel,
                value: shop.contactPhone,
              ),
              const _SheetDivider(),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: _CallButton(
                  label: strings.callButton,
                  onTap: () => launchUrl(Uri.parse('tel:${shop.contactPhone}')),
                ),
              ),

              // the catalogue goes last, below the call button, on purpose: someone who opened a
              // pin wants to know where the shop is and how to reach it first. browsing prices is
              // the longer, scrollable part of the visit, so it goes where scrolling starts.
              const _SheetDivider(),
              _ShopProductsSection(shop: shop, strings: strings),
            ],
          ),
        ),
      ),
    );
  }
}

// the customer-facing half of the products feature: the same two-per-row grid the owner manages,
// rendered read-only.
//
// stateful only to kick off the fetch - the products themselves live in ProductsController, keyed
// by shop, so tapping the same pin twice in one session doesn't hit the network again.
class _ShopProductsSection extends StatefulWidget {
  const _ShopProductsSection({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  State<_ShopProductsSection> createState() => _ShopProductsSectionState();
}

class _ShopProductsSectionState extends State<_ShopProductsSection> {
  @override
  void initState() {
    super.initState();
    // deferred past the first frame for the same reason MapScreen defers its own load:
    // loadProducts notifies before its first await, and notifying while the tree is still building
    // trips flutter's "setState() called during build" guard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductsController>().loadProducts(widget.shop.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final controller = Provider.of<ProductsController>(context);
    final shopId = widget.shop.id;

    // only products the shop has actually priced. an unpriced row is a real product the owner
    // simply hasn't got to yet - useful to *them*, which is why their own grid shows it - but to a
    // customer it is a tile that answers no question, and fifty of them would bury the priced ones.
    final priced = [
      for (final product in controller.productsFor(shopId))
        if (product.hasPrice) product,
    ];

    final Widget content;
    if (controller.isLoadingFor(shopId) && !controller.hasLoaded(shopId)) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primaryOrange),
          ),
        ),
      );
    } else if (priced.isEmpty) {
      // a shop that hasn't priced anything gets a line saying so rather than a hidden section.
      // hiding it would make the sheet look like it simply has no products area, which is a
      // different (and wrong) message.
      content = Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          controller.loadErrorFor(shopId) != null
              ? strings.productsLoadError
              : strings.noPricedProductsYet,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    } else {
      content = ProductGrid(
        // shrink-wrapped: it is inside the sheet's own SingleChildScrollView, and two scrollables
        // fighting over one drag gesture is how a grid ends up refusing to move
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 4),
        tiles: [
          for (final product in priced)
            ProductTile(product: product, strings: strings),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                strings.shopProductsSectionTitle,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (priced.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${priced.length}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE1E4EA),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider({this.indent = 20});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: const SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
    );
  }
}

// rating and shop category on one line directly under the name. previously the rating floated on
// the far right of the title row, which is why it read as detached - as secondary metadata it
// belongs next to the other secondary metadata, not opposite the heading.
//
// the category is here as the legend for the map: the pin this sheet opened from draws a glyph for
// сантехника or обои, and this is the only place that says in words what the glyph meant. it is the
// same icon, so the two read as one fact seen twice rather than as two unrelated markings.
//
// the price comparison used to live on this line as well, squeezed in beside the rating. it moved
// down into _BasketPriceBlock: the сум figure came off the map pin in the same change, and a number
// that large next to a 13px rating had nowhere to go.
class _ShopMetaLine extends StatelessWidget {
  const _ShopMetaLine({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // the separator dot goes with the rating, not with the category. left behind it would open
        // the line with a bullet pointing at nothing. see Shop.hasRating.
        if (shop.hasRating) ...[
          const Icon(CupertinoIcons.star_fill, color: AppColors.starYellow, size: 13),
          const SizedBox(width: 4),
          Text(
            shop.rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const _MetaDot(),
        ],
        Icon(shop.category.icon, color: AppColors.textFaint, size: 13),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            shop.category.label(strings),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textGrey,
            ),
          ),
        ),
      ],
    );
  }
}

/// What the shared basket costs at this shop, and how that compares to the market.
///
/// **This is where the сум figure lives now.** It used to sit above the shop's pin on the map, where
/// forty seven-digit numbers were competing for the same few hundred pixels; the pin carries the
/// comparison alone (a coloured dot and "−4%") and the absolute price waits here, in the one place
/// there is room to label it. A number nobody can label is a number nobody can check.
///
/// The two fields are drawn from one condition rather than one each. Since migration 000013 a shop
/// is in the index only with its entire template priced, so `basketPrice` and `priceTier` are either
/// both present or both absent - branching on them separately would be writing code for a state the
/// database cannot produce.
///
/// **The empty case is a sentence, not a blank.** Most shops will sit here for a while: one unpriced
/// product is enough to keep a shop out. A customer who tapped a pin and found nothing where a price
/// should be reads that as the app failing, where a line saying the shop has not finished its prices
/// reads as the shop's own state - the same reason the notifications screen exists rather than the
/// bell doing nothing.
class _BasketPriceBlock extends StatelessWidget {
  const _BasketPriceBlock({required this.shop, required this.strings});

  final Shop shop;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final basket = shop.basketPrice;
    final tier = shop.priceTier;

    if (basket == null || tier == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(CupertinoIcons.clock, color: AppColors.textFaint, size: 13),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              strings.basketPriceIncomplete,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w400,
                color: AppColors.textFaint,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.basketPrice,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.2,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
              color: AppColors.textFaint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.somAmount(basket),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              height: 1.15,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 9),
          // the full sentence, not the compact form: this sheet is where somebody who just tapped a
          // pin reading "−4%" finds out what those four characters meant
          Align(
            alignment: Alignment.centerLeft,
            child: PriceTierBadge(
              tier: tier,
              differencePercent: shop.priceDifferencePercent,
              strings: strings,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(color: AppColors.textFaint, shape: BoxShape.circle),
    );
  }
}

// label above value, with a muted icon in the gutter. the label being small and faint is what lets
// the value itself stay readable at a normal weight instead of needing bold to stand out.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  /// left padding + icon width + gap - the x offset the text column starts at
  static const double textInset = 20 + 16 + 12;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Icon(icon, color: AppColors.textFaint, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    letterSpacing: 0.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textFaint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.accent(AppColors.primaryOrange),
      ),
      child: Material(
        color: AppColors.primaryOrange,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.phone_fill, color: Colors.white, size: 16),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
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
    );
  }
}

class _MapMessageBanner extends StatelessWidget {
  const _MapMessageBanner({
    required this.message,
    this.isBusy = false,
    this.isError = false,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isBusy;
  final bool isError;

  /// An optional control at the right-hand end of the pill - «Повторить» on the error banner, and
  /// nothing at all on the other three, which report a state the user cannot act on.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Overrides the glyph the two flags above would otherwise pick. The zoom hint is the one banner
  /// that is neither an error nor "there is nothing here", so a struck-through pin would tell the
  /// user the opposite of what the line next to it says.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // centred and content-sized rather than stretched edge to edge: a short line of text in a
    // full-width bar looks like a system error banner, not a status hint
    return Center(
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryOrange,
                  ),
                )
              else
                Icon(
                  icon ??
                      (isError
                          ? CupertinoIcons.exclamationmark_circle_fill
                          : CupertinoIcons.map_pin_slash),
                  color: isError ? AppColors.danger : AppColors.textFaint,
                  size: 15,
                ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isError ? AppColors.danger : AppColors.textGrey,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                // a divider rather than a gap: the pill is one small surface and the label beside
                // the button is a sentence, so without a rule between them the two read as one
                // run-on line and the tappable half is not obviously tappable.
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: AppColors.hairline,
                ),
                GestureDetector(
                  onTap: onAction,
                  // opaque, so the whole padded box takes the tap and not just the glyph shapes -
                  // this is a 13px label and the padding is most of the target
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
      ),
    );
  }
}

// shown at the top of a shop's details sheet: the shop's real photo once that feature exists,
// or - for now, since shops don't have photos yet - a neutral placeholder instead
class ShopBanner extends StatelessWidget {
  const ShopBanner({super.key, required this.imageUrl});

  final String? imageUrl;

  static const double height = 96;

  @override
  Widget build(BuildContext context) {
    // foreground decoration paints the outline *over* the clipped child, so the same hairline
    // frames a real photo and the placeholder alike
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const _DefaultBanner(),
              )
            : const _DefaultBanner(),
      ),
    );
  }
}

// was a full-bleed saturated orange gradient, which made the loudest thing in the sheet a
// placeholder for missing content. now a near-neutral surface with the faintest warm tint, so the
// shop's name is what the eye lands on first.
class _DefaultBanner extends StatelessWidget {
  const _DefaultBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ShopBanner.height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primarySoft, AppColors.surfaceMuted],
        ),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.building_2_fill,
          color: AppColors.primaryOrange.withValues(alpha: 0.42),
          size: 30,
        ),
      ),
    );
  }
}
