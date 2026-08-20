import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';
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

  /// Opens the shop card **as a draggable sheet over the map**.
  ///
  /// The card itself is the same one a VIP card and a Лучшие предложения row open, and that is the
  /// point: a shop is one object and it should look like one wherever it is reached from. Only the
  /// chrome differs, and only here - see the class comment on [ShopCardScreen].
  ///
  /// **Why a sheet again, when the sheet was the thing that got deleted.** What was deleted was a
  /// shop card *built inside this file*: the map owned a screen three other surfaces needed, so a
  /// paid VIP placement was a card that did nothing when it was tapped. Pushing a route fixed that by
  /// making the card reachable from anywhere, and cost the map the thing a map is for - a tap
  /// replaced the map entirely, so comparing three nearby shops was three pushes and three pops, each
  /// one rebuilding the map. The shop card stays shared; the map gets its overlay back.
  void _openShopCard(BuildContext context, Shop shop) {
    showShopCardSheet(context, shop);
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
                  onTap: () => _openShopCard(context, shop),
                  builder: () => ShopMarker(
                    // what the pin draws inside itself - универсальный, сантехника, древесные
                    // материалы or обои. always present, unlike the price label above: a shop's
                    // category is picked when it is created and never changes.
                    category: shop.category,
                    // omitted entirely for a shop that has not priced its whole catalogue,
                    // which is most of them early on - matches the shop card the pin opens.
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
                      // the camera moves first, so popping the card lands back on a map
                      // already centred on the shop that was picked
                      _flyTo(shop.latitude, shop.longitude);
                      _openShopCard(context, shop);
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
