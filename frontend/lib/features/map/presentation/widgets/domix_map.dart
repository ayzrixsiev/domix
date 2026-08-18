import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
// three libraries, one prefix. the package splits its public surface across several entrypoints -
// `mapkit` has the map, camera and map objects, `ui_view` has ViewProvider, `yandex_map` has the
// widget - and giving them one prefix keeps the SDK visibly separate from our own types below.
import 'package:yandex_maps_mapkit_lite/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit_lite/mapkit_factory.dart' as ymk;
import 'package:yandex_maps_mapkit_lite/ui_view.dart' as ymk;
import 'package:yandex_maps_mapkit_lite/yandex_map.dart' as ymk;
import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/constants/map_config.dart';

/// The whole surface between Domix and Yandex MapKit.
///
/// **Everything that knows MapKit exists lives in this file.** The screens above it deal in
/// latitudes, zoom levels and [MapPin]s and never import the SDK - which is the same shape the map
/// had when it was `flutter_map`, and the reason swapping the provider touched two screens rather
/// than twenty. If a third provider ever happens, this is the file that changes.
///
/// ---
///
/// **Why the pins are still Flutter widgets.** MapKit draws the map natively, so a marker is not a
/// widget in the tree - it is a bitmap handed to the renderer. The obvious reading of that is that
/// our `ShopMarker` would have to be redrawn as an image, and the price label with it. It does not:
/// [ymk.ViewProvider] takes a widget builder, lays the widget out off-screen against a
/// `RenderRepaintBoundary`, and gives MapKit the resulting raster. So the pin on the map is the same
/// widget the app has always drawn, and changing it stays a Flutter edit.
///
/// Two consequences of it being a *raster* rather than a live widget, and both are handled here:
///
/// - **No `InheritedWidget`s reach it.** ViewProvider builds against a bare `MediaQuery` +
///   `Directionality`; there is no `Theme`, no `Provider`, no `DefaultTextStyle` above the builder.
///   A pin widget must therefore be self-contained - `ShopMarker` already was, since it reads only
///   `AppColors` and `AppRadius` constants, but a future pin that calls `Theme.of(context)` would
///   throw off-screen and nowhere else.
/// - **A `GestureDetector` inside it does nothing.** A picture cannot be tapped. Taps arrive through
///   [ymk.MapObjectTapListener] instead, which is why [MapPin.onTap] exists as a field rather than
///   being wired up inside the widget.
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

  /// What to draw. Rebuilt wholesale whenever the list stops comparing equal - see
  /// [_MapPinIdentity] for why that is cheap enough.
  final List<MapPin> pins;

  /// Fires on every camera frame, including programmatic moves. Keep the work inside it trivial.
  final void Function(double zoom)? onZoomChanged;

  /// The camera's centre, reported only once it has come to rest. Separate from [onZoomChanged]
  /// because the location picker reverse-geocodes off it and must not fire a network request per
  /// frame of a fling.
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

  /// Glides the camera to a point. Where `flutter_map` needed an `AnimationController` and a pair of
  /// tweens driven frame by frame - `MapController.move()` being an instant jump - MapKit animates
  /// natively, so the whole hand-rolled camera tween the old map screen carried is gone.
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

  /// Everything about how this pin *looks*, as a string.
  ///
  /// Doing double duty, which is why it is required rather than derived. It decides when the pin
  /// list needs rebuilding at all, and it is handed to MapKit as the raster cache key - so forty
  /// шт of "универсальный, зелёный, −4%" are laid out and rasterized once between them instead of
  /// forty times. Two pins that draw identically **must** produce the same key, and two that do not
  /// must not.
  final String visualKey;

  /// Built off-screen by MapKit, not mounted in the tree. See the note on [DomixMap].
  final Widget Function() builder;

  final VoidCallback? onTap;

  /// Which point of the rasterized widget sits on the coordinate, normalized. The default (0.5, 1.0)
  /// is bottom-centre, which is where a teardrop pin's tip is - anchoring at the centre instead
  /// would float every shop half a pin north of where it actually is.
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
      a.visualKey == b.visualKey;
}

/// **MapKit downloads nothing until `mapkit.onStart()` is called, and that is not optional.**
///
/// The map surface renders without it - the GL context comes up, the grid and the Yandex logo draw,
/// every camera call works - so the failure looks like a broken API key rather than a missing call.
/// It is not: the giveaway is the Yandex dashboard reporting **zero requests**, because a rejected
/// key still counts as a request and an unstarted MapKit never makes one. That cost a day.
///
/// `onStart`/`onStop` are on the global `mapkit` singleton rather than on a map, so they cannot
/// simply live in one widget's `initState`/`dispose`: `location_picker_screen` can be pushed over
/// `map_screen`, and the second map disposing would stop the network layer under the first one that
/// is still on screen. Hence a count of live maps rather than a boolean.
///
/// The app's own foreground state is the other half. MapKit keeps sockets and caches warm while
/// started, which is exactly what should not happen while the phone is in a pocket - and it is what
/// `onStop` is documented for ("the application pauses and goes to the background").
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

  /// **These are fields, not locals, and that is load-bearing.** MapKit holds its listeners by weak
  /// reference: anything only the native side points at is collected on the next GC and the
  /// callbacks silently stop arriving. Keeping them alive is the Dart side's job, and the failure
  /// mode - a map that works for ten seconds and then stops responding to the camera - looks nothing
  /// like its cause.
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

  /// `resumed` is the only state where the app is actually on screen and interactive. `inactive`
  /// covers a phone call banner or the app switcher, `paused` and `hidden` mean it is behind
  /// something - none of those are a reason to keep tiles downloading.
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
      // north stays up, permanently. our pins are teardrops with a text label above them, so a
      // two-finger twist would leave every one of them lying on its side with the price upside
      // down. flutter_map needed a bitmask and a separate desktop-only opt-out for this; MapKit has
      // two booleans, and tilt has to go for the same reason - a pin drawn flat on a tilted plane
      // is unreadable.
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

  /// Clears the collection and re-adds every pin.
  ///
  /// Deliberately not a diff. The shop list is fetched once per session and then changes only when
  /// an owner adds or deletes a shop, or when the zoom threshold flips the whole list on and off -
  /// so this runs a handful of times in a session, over at most a few hundred objects. A keyed diff
  /// would be more code, more state and one more thing that can disagree with the map on screen, to
  /// optimize something that is not on a hot path. If pins ever start moving continuously (live
  /// couriers, say), revisit it then.
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

// ---------------------------------------------------------------------------
// Listener adapters.
//
// MapKit's listeners are abstract classes rather than typedefs, so each one needs a real
// implementation. These three exist only to turn them back into callbacks.
// ---------------------------------------------------------------------------

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

/// Shown in place of the map when MapKit cannot run.
///
/// **Both cases it covers are developer-facing, not user-facing.** A shipped build is Android with a
/// key compiled in, and `make release` refuses to produce one without the key - so neither branch can
/// reach a customer. It exists because the alternative on a desktop `flutter run` is a crash on a
/// missing plugin before the first frame, which would make the whole app untestable on a laptop
/// rather than just its map.
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
