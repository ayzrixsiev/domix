import 'package:flutter/foundation.dart';

/// Where the map comes from, and whether it can run at all on this machine.
///
/// **Yandex MapKit Lite, not raster tiles.** The app used to draw OpenStreetMap and then Mapbox
/// tiles through `flutter_map` - `{z}/{x}/{y}` images with our own pins painted on top. Yandex does
/// not sell that: their licence forbids pulling tiles outside their own SDK, so there is no
/// "swap the URL" version of this. MapKit renders the map itself, natively, and we hand it map
/// objects instead of drawing markers ourselves.
///
/// **Why the move was worth a rewrite of the map feature.** Mapbox bills the way we were using it -
/// the Static Tiles API - **per tile request**: 200 000 free per month, then $0.50 per 1 000. A
/// single person opening the map costs tens of requests, so the budget is measured in map sessions
/// and it shrinks as people pan. MapKit bills **per monthly active user**: 25 000 MAU on the Free
/// licence, and panning is free. At our scale that is the difference between watching a meter and
/// not having one.
///
/// The Free licence's conditions are ones we already meet: the app is free to download, we do not
/// use it for turn-by-turn navigation, and we do not run monitoring or dispatch. If any of those
/// three ever changes, the licence has to be revisited before the code does.
///
/// **Lite, deliberately.** `yandex_maps_mapkit_lite` is the free-licence package: map display, map
/// objects, camera, user location. The full `yandex_maps_mapkit` adds search, routing and panoramas,
/// which are the paid parts and which we do not use - address search and reverse geocoding stay on
/// Nominatim (`geocoding_service.dart`), unchanged by this move.
///
/// ---
///
/// **MapKit is Android and iOS only, and that is a change to how the map gets tested.**
///
/// The plugin registers for exactly two platforms. `flutter_map` was pure Dart and drew fine on a
/// Linux desktop and in Chrome, which is how the map screen has been eyeballed until now. It cannot
/// any more: every map screen needs a phone or an emulator. [isSupportedPlatform] is what lets the
/// rest of the app keep running on a desktop instead of crashing on a missing plugin - the map
/// screens check it and show an explanatory panel.
class MapConfig {
  /// The MapKit API key, compiled in with `--dart-define` (see `env.json` / `env.prod.json`).
  ///
  /// Obtained from Yandex's developer dashboard and **not a secret in the sense `JWT_SECRET` is** -
  /// it ships inside the APK and can be read out of it, like any client map key. It is still
  /// attached to a quota and a billing account, so treat it as abusable rather than leakable, and
  /// rotate it in the dashboard if usage looks wrong.
  static const String apiKey = String.fromEnvironment('MAPKIT_API_KEY');

  static bool get hasApiKey => apiKey.isNotEmpty;

  /// Whether MapKit's native plugin exists on the platform we are running on.
  ///
  /// `defaultTargetPlatform` rather than `Platform.isAndroid`: `dart:io` is not available on web, so
  /// importing it here would break a `flutter build web` and a widget test alike.
  static bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// The map can only draw when the plugin exists *and* a key was compiled in. Both failures look
  /// the same to a user - no map - so the screens branch on one getter and explain which it was.
  static bool get isAvailable => isSupportedPlatform && hasApiKey;

  /// Why the map is not drawing, for the placeholder panel. Null when it is fine.
  ///
  /// Deliberately a machine-readable enum rather than a string: the wording is localized in
  /// `app_localizations.dart` like everything else the user reads.
  static MapUnavailableReason? get unavailableReason {
    if (!isSupportedPlatform) return MapUnavailableReason.unsupportedPlatform;
    if (!hasApiKey) return MapUnavailableReason.missingApiKey;
    return null;
  }
}

enum MapUnavailableReason {
  /// Running on desktop or web, where MapKit has no native side. A developer-facing state: it
  /// cannot happen on a shipped build, which is Android only.
  unsupportedPlatform,

  /// Built without `MAPKIT_API_KEY`. `make release` refuses to produce a build in this state, so
  /// like the above this is something only a developer sees.
  missingApiKey,
}
