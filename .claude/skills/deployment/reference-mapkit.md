# Yandex MapKit Lite

Read when touching the map, `domix_map.dart`, pins, or a Gradle failure that mentions Kotlin or compileSdk.

---

## Yandex MapKit Lite

The map is drawn natively by MapKit. Yandex's licence forbids pulling their tiles outside their SDK,
so there was no "swap the URL" version of the migration off `flutter_map`.

Billing is **monthly active users** (25 000 free), not per-request. **Free tier or not, there is no
hard cap: set a billing alert.** The Free licence requires: free to download, no turn-by-turn
navigation, no monitoring or dispatch. **If any of those three changes, revisit the licence before
the code.**

**Lite, not the full package.** `yandex_maps_mapkit_lite` gives map, map objects, camera, user
location. Search, routing and panoramas are paid and unused — address search and reverse geocoding
**stay on Nominatim**.

**`domix_map.dart` is the entire boundary.** `DomixMap`, `DomixMapController` and `MapPin` are all
the screens see; nothing outside that file imports the SDK. **Keep it that way.**

### Traps, all of them silent

- **MapKit downloads nothing until `mapkit.onStart()` is called, and every symptom points elsewhere.**
  The surface comes up without it: GL context created, grey grid and Yandex logo drawn, camera moves,
  logcat shows `Chosen EGL config` — and not one error. It reads exactly like a rejected API key. The
  one signal that separates them is the **Yandex dashboard: zero requests.** A rejected key still
  counts as a request; an unstarted MapKit never makes one. Ping the tile host first to rule out the
  network (`adb shell ping core-renderer-tiles.maps.yandex.net`).
- **`onStart`/`onStop` live on the global `mapkit` singleton**, not on a map, so they cannot sit in
  one widget's `initState`/`dispose` — `location_picker_screen` can be pushed over `map_screen`, and
  the second map's `dispose` would stop the network layer under the first. `domix_map.dart` keeps a
  **count of mounted maps** plus the app's foreground state, and `_syncMapkitLifecycle()` reconciles
  them; it no-ops when MapKit already matches, since `onStart` is not documented as idempotent. The
  singleton also means `mapkit_factory.dart` must be imported separately.
- **MapKit holds listeners by weak reference.** Camera, input and per-pin tap listeners are all
  fields on `_DomixMapState`, never locals. Anything only the native side points at is collected on
  the next GC and the callbacks silently stop — a map that works for ten seconds then ignores the
  camera, with nothing in any log.
- **Pins are Flutter widgets rasterized off-screen.** `ViewProvider` takes a widget _builder_, lays
  it out against a `RenderRepaintBoundary` and hands MapKit the raster. Two consequences: **no
  `InheritedWidget` reaches a pin** (a pin calling `Theme.of(context)` throws off-screen and nowhere
  else), and **a `GestureDetector` inside a pin does nothing** (taps arrive through
  `placemark.addTapListener` — hence `MapPin.onTap` is a field and `ShopMarker.onTap` is always null
  on the map).
- **`MapPin.visualKey` does two jobs and must capture every visual difference.** It decides when the
  pin list is rebuilt _and_ it is MapKit's raster cache key. A key that misses a difference caches
  the wrong bitmap; a key including the shop's name defeats the cache.

### Three things in `android/` exist only because of MapKit

- **`compileSdk` forced to 36 for every plugin subproject** (`android/build.gradle.kts`). MapKit
  compiles against 35; `flutter_plugin_android_lifecycle` — which MapKit depends on — requires 36+.
  **The placement is load-bearing twice:** `afterEvaluate` rather than `plugins.withId` (withId fires
  as the plugin is _applied_, and its build file then sets 35 straight back), and registered inside
  the _first_ `subprojects` block, because the later one calls `evaluationDependsOn(":app")` and an
  `afterEvaluate` added after that throws `Cannot run Project.afterEvaluate(Action) when the project
  is already evaluated`.
- **`play-services-location`** declared in `app/build.gradle.kts` — MapKit's location layer needs it,
  the plugin does not pull it in, and without it the app compiles and dies at runtime.
- **Gradle's heap cap** in `android/gradle.properties` — see `frontend/CLAUDE.md`.

### Permissions MapKit merges in

Seven, none of which we ask for: `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`,
`ACCESS_FINE_LOCATION`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`. They show up on
the Play listing. **Do not strip them blind with `tools:node="remove"`** — a native SDK that checks
for a permission it declared can fail at runtime, and only on a device. `ACCESS_FINE_LOCATION` is the
one Play makes you justify.

### What the move cost

**`minSdk` 24 → 26** (MapKit's floor), **building needs JDK 21+**, and **the map no longer runs on
desktop or web** (`MapConfig.isSupportedPlatform` keeps the rest of the app running there, with
`MapUnavailablePanel` in the map's place).

The build warns that plugins applying the Kotlin Gradle Plugin — `yandex_maps_mapkit_lite` — will
fail on future Flutter versions. Yandex's to fix; **if a Flutter upgrade fails on Kotlin, this is
why.**

Attribution is MapKit's job now. The hand-rolled `_MapAttribution` pill is deleted, not moved — it
existed for OpenStreetMap's ODbL requirement, and adding ours back would credit the wrong party.
