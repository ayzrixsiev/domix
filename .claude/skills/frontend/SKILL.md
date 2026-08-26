---
name: frontend
description: >
  Core architectural rules, visual tokens, layout philosophies, and Flutter toolchain constraints 
  for the Domix mobile app. Use when building UI screens, working with the map, managing state, 
  or applying styling.
---

# Domix Frontend Architecture & UI Rules

### Architecture & Layout

The app follows a feature-first structure (`lib/features/<feature>/{data,presentation}`). We use `ChangeNotifier` view-models provided as singletons via `MultiProvider`. The app deliberately ignores the device's font-size settings using `MediaQuery.withNoTextScaling` and locks to portrait mode because our UI relies on fixed-height cards that would otherwise overflow.

### Design System & Components

Visual tokens live in `app_theme.dart` and `app_colors.dart` (using specific radii scales). Brand orange is strictly reserved for primary actions, while `trackGrey` is used for elements sitting directly on the `0xFFEFF1F5` background. Do not hand-roll back buttons or empty states; universally use `CircleBackButton` and `EmptyStateView`. For tap feedback on large tiles, we use `PressableScale` instead of ink ripples because ripples fail to provide clear visual feedback on bordered shapes. We exclusively use `flutter_lucide` for icons.

### Home Screen & Feeds

The home screen does not invent fallback data. VIP and "Best Offers" use a fixed number of slots (5 and 15). Unsold slots are drawn at full visual strength to act as advertisements for the placement. The VIP carousel snaps to the center using an unbounded forward-only `PageView`.

### Map Mechanics & Pins

The map is strictly rotation-locked and tilt-locked so that teardrop pins and price labels stay upright. Pins are completely withheld below a zoom level of 13 to prevent visual clutter. A map pin conveys two distinct channels of information: the teardrop carries a Lucide glyph for the shop's category, and a separate label carries the price comparison.

### Toolchain & Workflows

Building for Android strictly requires JDK 21+ due to Yandex MapKit's bytecode requirements. We cap the Gradle heap to 4GB in `gradle.properties` to prevent OutOfMemory errors on standard laptops. We use `make dev` for Android testing (which supports the map) and `make desktop` with `DevicePreview` for rapid UI layout testing (which lacks map support but runs faster).
