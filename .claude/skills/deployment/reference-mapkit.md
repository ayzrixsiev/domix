# Yandex MapKit Lite

Read when touching the map, `domix_map.dart`, pins, or a Gradle failure that mentions Kotlin or compileSdk.

---

## Yandex MapKit Lite

The map is drawn natively by MapKit. Yandex's licence forbids pulling their tiles outside their SDK,
so there was no "swap the URL" version of the migration off `flutter_map`.

**The free licence is 1 000 DAU — daily unique users opening the map — on the yandex.ru terms that
apply to us** (checked 2026-09-26, `yandex.ru/dev/tariffs/doc/ru/mapkit/prices/`). **yandex.com shows
a different, international licence (25 000 MAU) — do not quote it.**
Paid plans are annual (5 000 DAU 195 000 ₽/yr, 20 000 DAU 585 000 ₽/yr …) **or monthly** (5 000 DAU
20 800 ₽/mo, 20 000 DAU 58 500 ₽/mo), the minimum payment non-refundable; a 7-day trial covers 100 DAU.
At 300–400 users DAU is far below 1 000. **There is no hard cap: set a usage alert.**

The free licence requires: free to download and open registration, no turn-by-turn navigation, no
real-time tracking of vehicles or staff, Yandex's logo and copyright untouched, **a link to
`https://yandex.ru/legal/maps_api/` in the app's «О приложении»** (`AboutScreen`, reachable by guests
too). **If any of these changes, revisit the licence before the
code.** Phase three's job tickets are the likeliest thing to touch "tracking staff".

**Lite, not the full package.** `yandex_maps_mapkit_lite` gives map, map objects, camera, user
location. Search, routing and panoramas are paid and unused — address search is the separate HTTP
**Geocoder** and **Geosuggest**, called by the api with keys the app never holds (`internal/geo`),
and a shop card's «Маршрут» hands the destination to whatever maps app the phone has (`rtext` with
an empty origin), which draws the route from a position we never ask for.
«О приложении» carries both links the terms name: `maps_api` and `maps_termsofuse`.

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
- **Gradle's heap cap** in `android/gradle.properties` — see the `frontend` skill.

### Permissions MapKit merges in

Seven, none of which we ask for: `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`,
`ACCESS_FINE_LOCATION`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`. They show up on
the Play listing. **Do not strip them blind with `tools:node="remove"`** — a native SDK that checks
for a permission it declared can fail at runtime, and only on a device. `ACCESS_FINE_LOCATION` is the
one Play makes you justify.

**Each permission also implies its hardware as a required feature**, and Play refuses to send a
release for review while `android.hardware.wifi` is required (it was, from the two wifi permissions,
until 1.0.1+5). The app manifest declares wifi and location `required="false"`; check
`aapt dump badging … | grep uses-implied-feature` after any SDK upgrade for a new one.

### What the move cost

**`minSdk` 24 → 26** (MapKit's floor), **building needs JDK 21+**, and **the map no longer runs on
desktop or web** (`MapConfig.isSupportedPlatform` keeps the rest of the app running there, with
`MapUnavailablePanel` in the map's place).

The build warns that plugins applying the Kotlin Gradle Plugin — `yandex_maps_mapkit_lite` — will
fail on future Flutter versions. Yandex's to fix; **if a Flutter upgrade fails on Kotlin, this is
why.**

Attribution is MapKit's job now. The hand-rolled `_MapAttribution` pill is deleted, not moved — it
existed for OpenStreetMap's ODbL requirement, and adding ours back would credit the wrong party.
