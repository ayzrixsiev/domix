import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/features/map/data/user_location_service.dart';
import 'package:frontend/features/map/presentation/controllers/map_focus_controller.dart';
import 'package:frontend/features/stores/data/shop_category.dart';
import 'package:frontend/features/stores/data/shop_model.dart';
import 'package:frontend/features/stores/presentation/controllers/stores_controller.dart';
import 'package:frontend/features/stores/presentation/screens/shop_card_screen.dart';
import '../widgets/domix_map.dart';
import '../widgets/map_category_bar.dart';
import '../widgets/map_search_panel.dart';
import '../widgets/shop_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.isActive = true,
    this.onExit,
  });

  final bool showScaffold;

  /// What the map has to keep clear at its foot. **Zero inside the shell**, which hides the nav bar
  /// for this tab - the map is the whole screen, and the only thing left to clear is the system
  /// inset, which this screen adds itself.
  final double bottomPadding;

  /// The way back to the rest of the app, drawn as the disc left of the search field. **Null means
  /// no disc**: a MapScreen opened on its own route has the system back gesture, and a button that
  /// popped nothing would be a dead control.
  final VoidCallback? onExit;

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

  /// where «Рядом со мной» lands: a few streets around the user, which is what "nearby" means on
  /// foot or by car. tighter than [_focusedZoom], which is aimed at one address.
  static const _nearMeZoom = 15.0;

  /// the band at the foot of the map that nothing of ours is drawn in - it belongs to Yandex's logo
  /// and copyright line, which MapKit paints there and the licence requires be visible
  static const _logoClearance = 30.0;

  /// the whole city fits at this zoom, which is why the map opens here
  static const _initialZoom = 12.0;

  /// Below this zoom a shop is a [ShopDot] and above it a full [ShopMarker]. **not a cutoff where pins
  /// disappear**: at city scale the drawing is unreadable, but *where the shops are* is what a
  /// zoomed-out map is for, so only the detail is withheld.
  ///
  /// 13 and not 12: the map opens at [_initialZoom] showing the scatter, and one pinch turns it into
  /// pins that can be read. It belongs to the pin rather than to this screen because the pin's size
  /// curve starts here - see [ShopPinIcon.scaleForZoom].
  static const _minDetailZoom = ShopPinIcon.detailZoom;

  /// Below this zoom a pin carries no price label. **The label is 13px type and MapKit scales the
  /// whole marker**, so a label on a pin drawn at 70% is unreadable - and seventy of them at city
  /// scale overlap into a wall of white pills anyway. By the time one appears the pin is full size.
  static const _minLabelZoom = ShopPinIcon.fullScaleZoom;

  DomixMapController? _map;

  /// A bool rather than the zoom itself, and that is the point of the design: the camera listener
  /// fires on every frame of a pinch, so holding the zoom in state would rebuild the pin list sixty
  /// times a second.
  bool _detailedPins = _initialZoom >= _minDetailZoom;

  /// Same again for the price label, which comes in a zoom or two after the drawing does.
  bool _pinLabels = _initialZoom >= _minLabelZoom;

  /// null is every kind of shop. Lives here rather than in [StoresController] because it is a view
  /// of one screen's map, not a fact about the shop list - the home screen browses the same shops
  /// under its own categories.
  ShopCategory? _category;

  /// The chips start open: they are the feature, and a control nobody sees is a control nobody uses.
  bool _categoriesOpen = true;

  final _location = UserLocationService();

  /// The last fix, drawn as the blue dot. Kept for the session only - never stored, never sent.
  ({double latitude, double longitude})? _userLocation;
  bool _locating = false;

  /// Why the last press of «Рядом со мной» came back empty. Cleared by the next press, so the
  /// sentence on the banner is always about the button the user just pressed.
  UserLocationFailure? _locationFailure;
  Timer? _failureTimer;

  late final MapFocusController _focus;

  @override
  void initState() {
    super.initState();

    _focus = context.read<MapFocusController>()
      ..addListener(_showRequestedShop);

    // the first sync. IndexedStack keeps this State alive across tab switches, so this runs once per
    // session and every later re-sync comes through didUpdateWidget. deliberately not gated on
    // isActive: the shell builds every tab at launch, so the pins are in hand before Карта is pressed.
    _syncShops();
  }

  @override
  void dispose() {
    _focus.removeListener(_showRequestedShop);
    _failureTimer?.cancel();
    super.dispose();
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

  // a shop card's «Маршрут» lands here. **the request stays pending until the native map exists**, and
  // the filter is dropped when it would hide the very pin being shown
  void _showRequestedShop() {
    final map = _map;
    final shop = _focus.request;
    if (map == null || shop == null) return;

    _focus.take();
    if (_category != null && _category != shop.category) {
      setState(() => _category = null);
    }
    map.flyTo(shop.latitude, shop.longitude);
  }

  // fires on every camera frame, so it has to be cheap and must not setState unless the answer
  // changed. programmatic moves come through the same listener, which is what makes flying to a
  // search result bring the detail in on its own.
  void _onZoomChanged(double zoom) {
    final detailed = zoom >= _minDetailZoom;
    final labelled = zoom >= _minLabelZoom;
    if (detailed != _detailedPins || labelled != _pinLabels) {
      setState(() {
        _detailedPins = detailed;
        _pinLabels = labelled;
      });
    }
  }

  /// One shop, drawn as its trade. The price label is folded in here rather than at the call site
  /// because the tier decides both how the pin looks and what it is cached under, and a visual key
  /// that disagreed with the widget would serve the wrong bitmap for the rest of the session.
  MapPin _shopPin(Shop shop) {
    // omitted entirely for a shop that has not priced its whole catalogue, which is most of them
    // early on - and matches the shop card the pin opens
    final tier = _pinLabels ? shop.priceTier : null;

    return MapPin(
      id: shop.id.toString(),
      latitude: shop.latitude,
      longitude: shop.longitude,
      // everything that changes how this pin is drawn, and nothing that does not. the shop's name is
      // absent on purpose - two shops of the same category with the same comparison draw the same pin and
      // share one cached raster. see MapPin.visualKey.
      visualKey:
          '${shop.category.code}|${tier?.name ?? '-'}'
          '|${shop.priceDifferencePercent ?? 0}',
      // the drawing grows as the camera comes in, which is what makes it part of the map rather
      // than a sticker over it. applied to the raster, so it is not in the key above.
      scaleWithZoom: ShopPinIcon.scaleForZoom,
      onTap: () => _openShopCard(context, shop),
      // async, and that is what MapPin.builder takes a future for: the drawing has to be decoded
      // before MapKit takes the raster off this widget - see ShopPinIcon
      builder: () async {
        await ShopPinIcon.decoded(shop.category);
        return ShopMarker(
          // always present, unlike the price label: a shop's category is picked at creation and
          // never changes
          category: shop.category,
          priceTier: tier,
          priceDifferencePercent: shop.priceDifferencePercent,
        );
      },
    );
  }

  /// Opens the shop card **as a draggable sheet over the map** - the same card a VIP card and a
  /// Лучшие предложения row open, since a shop is one object wherever it is reached from. A sheet
  /// rather than a push, because comparing three nearby shops would rebuild the map three times.
  void _openShopCard(BuildContext context, Shop shop) {
    showShopCardSheet(context, shop);
  }

  /// One press of «Рядом со мной»: ask the phone once, move the camera, drop the blue dot.
  ///
  /// The fix is **not** cached between presses. A coordinate held from ten minutes ago would move
  /// the camera to where the user was, which is worse than the second of waiting - and asking again
  /// is what makes the button mean "now".
  Future<void> _goToUserLocation() async {
    if (_locating) return;

    _failureTimer?.cancel();
    setState(() {
      _locating = true;
      _locationFailure = null;
    });

    try {
      final point = await _location.current();
      if (!mounted) return;
      setState(() => _userLocation = point);
      _flyTo(point.latitude, point.longitude, zoom: _nearMeZoom);
    } on UserLocationException catch (e) {
      if (!mounted) return;
      setState(() => _locationFailure = e.failure);
      // **only the failure with nothing to press fades**: the other three carry «Настройки», which
      // would vanish under the finger
      if (e.failure == UserLocationFailure.unavailable) {
        _failureTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _locationFailure = null);
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _locationFailureMessage(
    UserLocationFailure failure,
    AppLocalizations strings,
  ) => switch (failure) {
    UserLocationFailure.servicesOff => strings.locationServicesOff,
    UserLocationFailure.denied => strings.locationDenied,
    UserLocationFailure.deniedForever => strings.locationDeniedForever,
    UserLocationFailure.unavailable => strings.locationUnavailable,
  };

  /// The one line over the map, or nothing. **Order is the message**: the location failure answers
  /// the button the user just pressed, so it outranks everything about the shop list, and "no shops
  /// in this category" only makes sense once there are shops to have filtered.
  Widget? _statusBanner(
    StoresController controller,
    List<Shop> visible,
    AppLocalizations strings,
  ) {
    if (_locationFailure case final failure?) {
      // the two failures a settings page can undo carry the button; the other two are just facts
      final actionable = failure != UserLocationFailure.unavailable;
      return _MapMessageBanner(
        message: _locationFailureMessage(failure, strings),
        isError: true,
        actionLabel: actionable ? strings.openSettingsButton : null,
        onAction: actionable ? () => _location.openSettingsFor(failure) : null,
      );
    }
    if (controller.isLoading && controller.stores.isEmpty) {
      return _MapMessageBanner(message: strings.loadingShops, isBusy: true);
    }
    if (controller.loadFailed && controller.stores.isEmpty) {
      // the retry is the whole point of this branch: the automatic re-sync only fires on a tab switch,
      // which is not something anyone should have to guess at
      return _MapMessageBanner(
        message: strings.mapLoadError,
        isError: true,
        actionLabel: strings.retryButtonShort,
        onAction: () => controller.loadStores(),
      );
    }
    if (controller.stores.isEmpty) {
      return _MapMessageBanner(message: strings.noShopsYet);
    }
    if (visible.isEmpty) {
      return _MapMessageBanner(message: strings.noShopsInCategory);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final controller = Provider.of<StoresController>(context);

    final shops = _category == null
        ? controller.stores
        : controller.stores
              .where((shop) => shop.category == _category)
              .toList();

    final statusBanner = _statusBanner(controller, shops, strings);

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
          onControllerReady: (controller) {
            _map = controller;
            _showRequestedShop();
          },
          // tapping the map itself drops the keyboard and closes the search dropdown
          onMapTap: () => FocusScope.of(context).unfocus(),
          pins: [
            for (final shop in shops)
              if (_detailedPins)
                _shopPin(shop)
              else
                MapPin(
                  // the same id as the detailed pin above, so switching between the two reads as one
                  // pin changing rather than every shop leaving and a new one arriving
                  id: shop.id.toString(),
                  latitude: shop.latitude,
                  longitude: shop.longitude,
                  visualKey: ShopDot.visualKey,
                  // centred on the point: a dot has no tip to stand on
                  anchor: const math.Point(0.5, 0.5),
                  // **a dot zooms in, it does not open the card.** at city scale a fingertip covers
                  // several dots, so opening a shop would be a coin toss the user has to undo; flying
                  // in resolves which dot was meant and costs nothing if it was the wrong one.
                  onTap: () =>
                      _flyTo(shop.latitude, shop.longitude, zoom: _nearMeZoom),
                  builder: () => const ShopDot(),
                ),
            // last, so it draws over the shops: where the user is standing is never the thing to hide
            if (_userLocation case final point?)
              MapPin(
                id: 'user-location',
                latitude: point.latitude,
                longitude: point.longitude,
                visualKey: UserLocationDot.visualKey,
                anchor: const math.Point(0.5, 0.5),
                builder: () => const UserLocationDot(),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: MapSearchPanel(
                    shops: controller.stores,
                    // only when there is nothing at all to search: a list that loaded before a failed
                    // refresh is still worth searching
                    shopsFailed:
                        controller.loadFailed && controller.stores.isEmpty,
                    strings: strings,
                    leading: switch (widget.onExit) {
                      final VoidCallback exit => MapBarButton(
                        icon: LucideIcons.chevron_left,
                        tooltip: strings.exitMap,
                        onTap: exit,
                      ),
                      _ => null,
                    },
                    action: MapBarButton(
                      // up folds the strip away, down brings it back: the arrow points where the
                      // strip is going, not at what it is hiding
                      icon: LucideIcons.chevron_up,
                      turns: _categoriesOpen ? 0 : 0.5,
                      tooltip: _categoriesOpen
                          ? strings.hideCategories
                          : strings.showCategories,
                      onTap: () =>
                          setState(() => _categoriesOpen = !_categoriesOpen),
                    ),
                    onShopSelected: (shop) {
                      // the camera moves first, so popping the card lands back on a map already centred on the shop
                      _flyTo(shop.latitude, shop.longitude);
                      _openShopCard(context, shop);
                    },
                    onPlaceSelected: (place) =>
                        _flyTo(place.latitude, place.longitude),
                  ),
                ),
                AnimatedSize(
                  duration: AppMotion.base,
                  curve: AppMotion.easing,
                  alignment: Alignment.topCenter,
                  child: _categoriesOpen
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: MapCategoryBar(
                            selected: _category,
                            strings: strings,
                            onSelected: (category) =>
                                setState(() => _category = category),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (statusBanner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: statusBanner,
                  ),
              ],
            ),
          ),
        ),

        // **viewPaddingOf, not paddingOf**: the second collapses to zero while the keyboard is up and
        // would drop the button onto the gesture bar every time the search field is tapped.
        //
        // clear of the foot because MapKit draws Yandex's logo along the bottom as a condition of the
        // licence - [_logoClearance] is the strip left for it.
        Positioned(
          right: 16,
          bottom:
              widget.bottomPadding +
              MediaQuery.viewPaddingOf(context).bottom +
              _logoClearance,
          child: _NearMeButton(
            label: strings.nearMe,
            isBusy: _locating,
            onTap: _goToUserLocation,
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
// copyright itself as a condition of the licence. the shell hides its nav bar for this tab, so that
// logo is now in clear air - keep the foot of the map that way.

/// «Рядом со мной» - the one control on the map that asks the phone a question. A pill rather than a
/// disc because it carries a verb: a bare arrow glyph over a map is read as a compass.
class _NearMeButton extends StatelessWidget {
  const _NearMeButton({
    required this.label,
    required this.isBusy,
    required this.onTap,
  });

  final String label;

  /// the fix can take a second or two indoors, and a button that does nothing for two seconds is a
  /// button the user presses again
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // still tappable while busy - the screen drops the second press, so this stays one control
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBusy)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryOrange,
                  ),
                )
              else
                // **not orange.** the glyph is a direction, not an action's accent, and the strip
                // above already spends the brand colour on the picked category.
                const Icon(
                  LucideIcons.navigation,
                  size: 17,
                  color: AppColors.textDark,
                ),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14.5,
                  height: 1.2,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isBusy;
  final bool isError;

  /// «Повторить» on the error banner, «Настройки» on the two location refusals a system page can
  /// undo, and nothing on the rest, which report a state the user cannot act on.
  final String? actionLabel;
  final VoidCallback? onAction;

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
                isError
                    ? CupertinoIcons.exclamationmark_circle_fill
                    : CupertinoIcons.map_pin_slash,
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
