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

  /// Whether this screen is the tab the user is looking at. **The shell's `IndexedStack` builds every
  /// tab and paints one**, so `build()` running says nothing about visibility and `initState` runs
  /// once for the life of the app - the false→true edge is what [didUpdateWidget] re-syncs on.
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

  /// the whole city fits at this zoom, which is why the map opens here - and why it is also where
  /// drawing every pin stops being useful
  static const _initialZoom = 12.0;

  /// Below this zoom the map draws no shop pins at all. MapKit culls off-screen objects itself; what
  /// culling cannot help with is being zoomed out over a city, where *every* shop is in the viewport -
  /// seventy `CustomPaint` pins that overlap into something unreadable anyway.
  ///
  /// 13 and not 12: at [_initialZoom] the map opens with the pins withheld and a line saying so, and
  /// one pinch brings them in. Search still reaches any shop from any zoom.
  static const _minShopZoom = 13.0;

  DomixMapController? _map;

  /// A bool rather than the zoom itself, and that is the point of the design: the camera listener
  /// fires on every frame of a pinch, so holding the zoom in state would rebuild the pin list sixty
  /// times a second.
  bool _shopsVisible = _initialZoom >= _minShopZoom;

  @override
  void initState() {
    super.initState();

    // the first sync. IndexedStack keeps this State alive across tab switches, so this runs once per
    // session and every later re-sync comes through didUpdateWidget. deliberately not gated on
    // isActive: the shell builds every tab at launch, so the pins are in hand before Карта is pressed.
    _syncShops();
  }

  /// Re-syncs when this becomes the visible tab. [StoresController.refreshStoresIfStale] decides
  /// whether that costs a request, which is what makes a failed load retry by itself instead of
  /// leaving a dead error banner.
  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // only the false→true edge: `isActive == true` on its own fires on every rebuild while the tab is
    // open, which with a live camera listener is a lot of them
    if (widget.isActive && !oldWidget.isActive) _syncShops();
  }

  /// Asks the controller to re-fetch if what it holds has gone stale, **on the next frame**: the
  /// deferral is not optional, since `loadStores()` notifies before its first `await` and both callers
  /// run inside the build phase.
  void _syncShops() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StoresController>().refreshStoresIfStale();
    });
  }

  // glides the camera instead of teleporting - MapKit animates natively, so this is one call
  void _flyTo(double latitude, double longitude, {double zoom = _focusedZoom}) {
    _map?.flyTo(latitude, longitude, zoom: zoom);
  }

  // fires on every camera frame, so it has to be cheap and must not setState unless the answer
  // changed. programmatic moves come through the same listener, which is what makes flying to a
  // search result bring the pins in on its own.
  void _onZoomChanged(double zoom) {
    final visible = zoom >= _minShopZoom;
    if (visible != _shopsVisible) {
      setState(() => _shopsVisible = visible);
    }
  }

  /// Opens the shop card **as a draggable sheet over the map** - the same card a VIP card and a
  /// Лучшие предложения row open, since a shop is one object wherever it is reached from. A sheet
  /// rather than a push, because comparing three nearby shops would rebuild the map three times.
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
    } else if (controller.loadFailed && controller.stores.isEmpty) {
      // the retry is the whole point of this branch: the automatic re-sync only fires on a tab switch,
      // which is not something anyone should have to guess at
      statusBanner = _MapMessageBanner(
        message: strings.mapLoadError,
        isError: true,
        actionLabel: strings.retryButtonShort,
        onAction: () => controller.loadStores(),
      );
    } else if (controller.stores.isEmpty) {
      statusBanner = _MapMessageBanner(message: strings.noShopsYet);
    } else if (!_shopsVisible) {
      // last, and only once there are shops: a map empty because it is zoomed out is a different fact
      // from one empty because the city has no shops, and saying the wrong one is worse than nothing
      statusBanner = _MapMessageBanner(
        message: strings.zoomInForShops(controller.stores.length),
        icon: LucideIcons.zoom_in,
      );
    }

    final body = Stack(
      children: [
        // deliberately NOT inside a SafeArea. a map is a canvas: it runs edge to edge and lets the status
        // bar float over it. wrapping it padded the whole notch band away and left a dead strip across the
        // top. only the controls further down are inset.
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
                  // everything that changes how this pin is drawn, and nothing that does not. the shop's name is
                  // absent on purpose - two shops of the same category with the same comparison draw the same pin and
                  // share one cached raster. see MapPin.visualKey.
                  visualKey:
                      '${shop.category.code}|${shop.priceTier?.name ?? '-'}'
                      '|${shop.priceDifferencePercent ?? 0}',
                  onTap: () => _openShopCard(context, shop),
                  builder: () => ShopMarker(
                    // always present, unlike the price label above: a shop's category is picked at creation and never
                    // changes
                    category: shop.category,
                    // omitted entirely for a shop that has not priced its whole catalogue, which is most of them early
                    // on - and matches the shop card the pin opens
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
                    // only when there is nothing at all to search: a list that loaded before a failed
                    // refresh is still worth searching
                    shopsFailed: controller.loadFailed && controller.stores.isEmpty,
                    strings: strings,
                    onShopSelected: (shop) {
                      // the camera moves first, so popping the card lands back on a map already centred on the shop
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

    // the clock and battery sit over light map tiles rather than over our own background, so they have
    // to be told to paint dark. AnnotatedRegion reverts when another screen takes over.
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

// the hand-rolled `_MapAttribution` pill here is **deleted**: MapKit draws Yandex's logo and
// copyright itself as a condition of the licence. if a future provider needs credit, it belongs
// above the nav bar at `bottomPadding + 10`.

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

  /// «Повторить» on the error banner, and nothing on the other three, which report a state the user
  /// cannot act on.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Overrides the glyph the two flags would otherwise pick: the zoom hint is neither an error nor
  /// "there is nothing here", and a struck-through pin would say the opposite of the line beside it.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // centred and content-sized rather than stretched edge to edge: a short line in a full-width bar
    // looks like a system error banner, not a status hint
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
                // a divider rather than a gap: without a rule between them the label and the button read as one
                // run-on line and the tappable half is not obviously tappable
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: AppColors.hairline,
                ),
                GestureDetector(
                  onTap: onAction,
                  // opaque, so the whole padded box takes the tap - this is a 13px label and the padding is most
                  // of the target
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
