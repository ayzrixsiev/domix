import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
// the package splits its public surface across several entrypoints; one prefix keeps the sdk
// visibly separate from our own types below
import 'package:yandex_maps_mapkit_lite/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit_lite/mapkit_factory.dart' as ymk;
import 'package:yandex_maps_mapkit_lite/ui_view.dart' as ymk;
import 'package:yandex_maps_mapkit_lite/yandex_map.dart' as ymk;
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/constants/map_config.dart';

/// The whole surface between Domix and Yandex MapKit: **everything that knows MapKit exists lives
/// in this file**, which is why swapping the provider touched two screens rather than twenty.
///
/// **The pins are still Flutter widgets** - [ymk.ViewProvider] lays one out off-screen and hands
/// MapKit the raster. Two consequences: **no `InheritedWidget`s reach it**, so a pin must be
/// self-contained or it throws off-screen and nowhere else; and **a `GestureDetector` inside it does
/// nothing**, which is why [MapPin.onTap] is a field.
class DomixMap extends StatefulWidget {
  const DomixMap({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.initialZoom,
    this.pins = const [],
    this.onZoomChanged,
    this.onMapTap,
    this.onCenterChanged,
    this.onControllerReady,
  });

  final double initialLatitude;
  final double initialLongitude;
  final double initialZoom;

  /// Rebuilt wholesale whenever the list stops comparing equal - see [_MapPinIdentity].
  final List<MapPin> pins;

  /// Fires on every camera frame, including programmatic moves. Keep the work inside it trivial.
  final void Function(double zoom)? onZoomChanged;

  /// reported only once the camera has come to rest: the location picker reverse-geocodes off it and
  /// must not fire a network request per frame of a fling
  final void Function(double latitude, double longitude)? onCenterChanged;

  /// A tap on the map itself, not on a pin.
  final VoidCallback? onMapTap;

  final void Function(DomixMapController controller)? onControllerReady;

  @override
  State<DomixMap> createState() => _DomixMapState();
}

/// What the screens above use to drive the camera. Handed out through
/// [DomixMap.onControllerReady] once the native map window exists.
class DomixMapController {
  DomixMapController._(this._window);

  final ymk.MapWindow _window;

  double get zoom => _window.map.cameraPosition.zoom;

  /// Glides the camera to a point. MapKit animates natively, so the hand-rolled camera tween the
  /// flutter_map version carried is gone.
  void flyTo(double latitude, double longitude, {double zoom = 16.0}) {
    _window.map.move(
      ymk.CameraPosition(
        ymk.Point(latitude: latitude, longitude: longitude),
        zoom: zoom,
        azimuth: 0,
        tilt: 0,
      ),
      animation: const ymk.Animation(
        type: ymk.AnimationType.Smooth,
        duration: 0.6,
      ),
    );
  }
}

/// One marker: where it goes, what it looks like, and what a tap on it does.
class MapPin {
  const MapPin({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.visualKey,
    required this.builder,
    this.onTap,
    this.anchor = const math.Point(0.5, 1.0),
  });

  /// Stable per shop, used to tell "the same pin moved" from "a different pin".
  final String id;

  final double latitude;
  final double longitude;

  /// Everything about how this pin *looks*, as a string. Doing double duty: it decides when the pin
  /// list needs rebuilding, and it is MapKit's raster cache key - so forty identical pins are
  /// rasterized once. Two pins that draw identically **must** produce the same key, and two that do
  /// not must not.
  final String visualKey;

  /// Built off-screen by MapKit, not mounted in the tree. See the note on [DomixMap].
  final Widget Function() builder;

  final VoidCallback? onTap;

  /// normalized; the default (0.5, 1.0) is bottom-centre, where a teardrop's tip is - anchoring at
  /// the centre would float every shop half a pin north of where it actually is
  final math.Point<double> anchor;
}

/// Compares two pin lists without holding on to the builders, which are closures and never equal.
class _MapPinIdentity {
  static bool sameList(List<MapPin> a, List<MapPin> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!same(a[i], b[i])) return false;
    }
    return true;
  }

  static bool same(MapPin a, MapPin b) =>
      a.id == b.id &&
      a.latitude == b.latitude &&
      a.longitude == b.longitude &&
      a.visualKey == b.visualKey &&
      // part of where the pin lands, not of how it looks, so the visual key cannot stand in for it:
      // a teardrop stands on the point and a dot sits centred over it
      a.anchor == b.anchor;
}

/// **MapKit downloads nothing until `mapkit.onStart()` is called, and that is not optional.** The
/// surface renders without it, so the failure looks like a broken API key - the giveaway is the
/// Yandex dashboard reporting **zero requests**, since a rejected key still counts as one.
///
/// `onStart`/`onStop` are on the global singleton, so they cannot live in one widget's initState:
/// the location picker can be pushed over the map screen, and the second map disposing would stop
/// the network layer under the first. Hence a count of live maps, plus the app's foreground state.
int _mountedMaps = 0;
bool _appInForeground = true;
bool _mapkitStarted = false;

/// Brings MapKit's actual state in line with what the app needs, and does nothing when they already
/// agree - `onStart` is not documented as idempotent and there is no reason to find out.
void _syncMapkitLifecycle() {
  if (!MapConfig.isAvailable) return;
  final shouldRun = _mountedMaps > 0 && _appInForeground;
  if (shouldRun == _mapkitStarted) return;
  _mapkitStarted = shouldRun;
  if (shouldRun) {
    ymk.mapkit.onStart();
  } else {
    ymk.mapkit.onStop();
  }
}

class _DomixMapState extends State<DomixMap> with WidgetsBindingObserver {
  ymk.MapWindow? _window;

  /// **Fields, not locals, and that is load-bearing.** MapKit holds its listeners weakly: anything
  /// only the native side points at is collected on the next GC and the callbacks silently stop - a
  /// map that works for ten seconds and then ignores the camera.
  late final ymk.MapCameraListener _cameraListener = _CameraListener(_onCameraChanged);
  late final ymk.MapInputListener _inputListener = _InputListener(
    onTap: (_, _) => widget.onMapTap?.call(),
  );

  /// Same reason: one tap listener per pin, retained here for as long as the pin is on the map.
  final List<ymk.MapObjectTapListener> _pinTapListeners = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mountedMaps++;
    _syncMapkitLifecycle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mountedMaps--;
    _syncMapkitLifecycle();
    super.dispose();
  }

  /// `resumed` is the only state where the app is actually on screen and interactive; none of the
  /// others is a reason to keep tiles downloading
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appInForeground = state == AppLifecycleState.resumed;
    _syncMapkitLifecycle();
  }

  @override
  void didUpdateWidget(covariant DomixMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_MapPinIdentity.sameList(oldWidget.pins, widget.pins)) {
      _renderPins();
    }
  }

  void _onMapCreated(ymk.MapWindow window) {
    _window = window;
    final map = window.map;

    map
      // north stays up, permanently: the pins are teardrops with a text label above them, so a twist
      // would leave every one lying on its side with the price upside down. tilt goes for the same
      // reason - a pin drawn flat on a tilted plane is unreadable.
      ..rotateGesturesEnabled = false
      ..tiltGesturesEnabled = false
      ..move(
        ymk.CameraPosition(
          ymk.Point(latitude: widget.initialLatitude, longitude: widget.initialLongitude),
          zoom: widget.initialZoom,
          azimuth: 0,
          tilt: 0,
        ),
      )
      ..addCameraListener(_cameraListener)
      ..addInputListener(_inputListener);

    _renderPins();
    widget.onControllerReady?.call(DomixMapController._(window));
  }

  void _onCameraChanged(
    ymk.Map map,
    ymk.CameraPosition position,
    ymk.CameraUpdateReason reason,
    bool finished,
  ) {
    widget.onZoomChanged?.call(position.zoom);
    // only when the camera has come to rest: `finished` is false for every intermediate frame of a
    // pinch, a fling or an animated flyTo, and the picker's reverse geocode is a network call.
    if (finished) {
      widget.onCenterChanged?.call(position.target.latitude, position.target.longitude);
    }
  }

  /// Clears the collection and re-adds every pin. Deliberately not a diff: the shop list changes a
  /// handful of times a session, over at most a few hundred objects, and a keyed diff would be one
  /// more thing that can disagree with the map on screen. Revisit if pins ever move continuously.
  void _renderPins() {
    final window = _window;
    if (window == null) return;

    window.map.mapObjects.clear();
    _pinTapListeners.clear();

    for (final pin in widget.pins) {
      final placemark = window.map.mapObjects.addPlacemarkWithViewStyle(
        ymk.Point(latitude: pin.latitude, longitude: pin.longitude),
        ymk.ViewProvider(
          builder: pin.builder,
          // `cacheable` without an `id` caches nothing useful, and an `id` that does not capture
          // every visual difference caches the *wrong* bitmap - see MapPin.visualKey.
          id: pin.visualKey,
          cacheable: true,
        ),
        ymk.IconStyle(anchor: pin.anchor),
      );

      if (pin.onTap case final onTap?) {
        final listener = _PinTapListener(onTap);
        _pinTapListeners.add(listener);
        placemark.addTapListener(listener);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MapConfig.unavailableReason case final reason?) {
      return MapUnavailablePanel(reason: reason);
    }
    return ymk.YandexMap(onMapCreated: _onMapCreated);
  }
}

// MapKit's listeners are abstract classes rather than typedefs, so each one needs a real
// implementation. These three exist only to turn them back into callbacks.

final class _CameraListener implements ymk.MapCameraListener {
  const _CameraListener(this._onChanged);

  final void Function(ymk.Map, ymk.CameraPosition, ymk.CameraUpdateReason, bool) _onChanged;

  @override
  void onCameraPositionChanged(
    ymk.Map map,
    ymk.CameraPosition cameraPosition,
    ymk.CameraUpdateReason cameraUpdateReason,
    bool finished,
  ) => _onChanged(map, cameraPosition, cameraUpdateReason, finished);
}

final class _InputListener implements ymk.MapInputListener {
  const _InputListener({required this.onTap});

  final void Function(ymk.Map, ymk.Point) onTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) => onTap(map, point);

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) {}
}

final class _PinTapListener implements ymk.MapObjectTapListener {
  const _PinTapListener(this._onTap);

  final VoidCallback _onTap;

  @override
  bool onMapObjectTap(ymk.MapObject mapObject, ymk.Point point) {
    _onTap();
    // true = handled, so the tap does not also fall through to the map's own input listener and
    // immediately close the sheet the pin just opened.
    return true;
  }
}

/// Shown in place of the map when MapKit cannot run. **Both cases are developer-facing**: a shipped
/// build is Android with a key compiled in, and `make release` refuses to produce one without it.
/// It exists so a desktop `flutter run` loses its map rather than crashing before the first frame.
class MapUnavailablePanel extends StatelessWidget {
  const MapUnavailablePanel({super.key, required this.reason});

  final MapUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = switch (reason) {
      MapUnavailableReason.unsupportedPlatform => (
        LucideIcons.smartphone,
        'Карта доступна на телефоне',
        'Yandex MapKit рисует карту нативно и существует только на Android и iOS. '
            'Запустите приложение на устройстве или эмуляторе.',
      ),
      MapUnavailableReason.missingApiKey => (
        LucideIcons.key_round,
        'Нет ключа MapKit',
        'Соберите с MAPKIT_API_KEY в env.json — см. make dev.',
      ),
    };

    return ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                child: Icon(icon, size: 28, color: AppColors.textFaint),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
