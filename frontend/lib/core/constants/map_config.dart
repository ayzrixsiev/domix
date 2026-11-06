import 'package:flutter/foundation.dart';

/// Where the map comes from, and whether it can run at all on this machine.
///
/// Yandex MapKit renders natively and its licence forbids pulling tiles outside the SDK. the free
/// tier holds only while the app stays free to download, unnavigated and undispatched. `_lite` is that
/// package; address search is Yandex's geocoder behind our api (GeocodingService). Android and iOS
/// only - see [isSupportedPlatform].
class MapConfig {
  /// The MapKit API key, compiled in with `--dart-define` (`env.json` / `env.prod.json`). It ships
  /// inside the APK and can be read out of it, so it is abusable rather than leakable - it is still
  /// attached to a quota, so rotate it in the dashboard if usage looks wrong.
  static const String apiKey = String.fromEnvironment('MAPKIT_API_KEY');

  static bool get hasApiKey => apiKey.isNotEmpty;

  /// Whether MapKit's native plugin exists here. `defaultTargetPlatform` rather than
  /// `Platform.isAndroid`: `dart:io` is missing on web and would break a web build and widget tests.
  static bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// The map draws only when the plugin exists *and* a key was compiled in. Both look the same to a
  /// user, so the screens branch on one getter and explain which it was.
  static bool get isAvailable => isSupportedPlatform && hasApiKey;

  /// Why the map is not drawing, for the placeholder panel. Null when it is fine. An enum rather
  /// than a string: the wording is localized like everything else the user reads.
  static MapUnavailableReason? get unavailableReason {
    if (!isSupportedPlatform) return MapUnavailableReason.unsupportedPlatform;
    if (!hasApiKey) return MapUnavailableReason.missingApiKey;
    return null;
  }
}

enum MapUnavailableReason {
  /// Desktop or web, where MapKit has no native side. Cannot happen on a shipped build.
  unsupportedPlatform,

  /// Built without `MAPKIT_API_KEY`. `make release` refuses to produce a build in this state.
  missingApiKey,
}
