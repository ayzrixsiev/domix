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

Anything that belongs to a session is wiped through `AuthController.onSessionEnded`, and fetched through `onSessionStarted` — `main()` is the one place allowed to wire both ends, which is what keeps `profile/` from importing `stores/` or `favorites/`.

**Сообщения and Заявки are placeholders.** Both tabs stay in the nav bar and say «скоро»: phase 1 is shops and customers, and a tab that disappears and returns moves every other tab twice. Do not rebuild either feature into them.

### Design System & Components

Visual tokens live in `app_theme.dart` and `app_colors.dart` (using specific radii scales). **The look is iOS: an off-white page (`background`, #F6F4F2, ~4% under a card) with pure-white cards lifted by the two-layer warm `AppShadows.card`** — the step alone is too small to separate them, so a card without the shadow disappears. Brand orange is strictly reserved for primary actions, while `trackGrey` is used for elements sitting directly on the page.

**The header sits flat on the page** (`AppPageHeader`: page colour, no band, no shadow; title 21/w800 with an optional subtitle) and `CircleIconButton` is a white disc with a shadow and **no ring**. **The bottom nav bar is full width and flush with the bottom edge** (`AppBottomNavBar`): `surfaceRaised`, a hairline on top, one orange pill sliding under the active tab. Tabs clear it by `AppBottomNavBar.height` plus the system inset, not a constant. Do not hand-roll back buttons or empty states; universally use `CircleIconButton` and `EmptyStateView`. For tap feedback on large tiles, we use `PressableScale` instead of ink ripples because ripples fail to provide clear visual feedback on bordered shapes. We exclusively use `flutter_lucide` for icons.

### Home Screen & Feeds

The home screen does not invent fallback data. VIP and "Best Offers" use a fixed number of slots (5 and 15). Unsold slots are drawn at full visual strength to act as advertisements for the placement. The VIP carousel snaps to the center using an unbounded forward-only `PageView`.

### Favourites

The heart on a product tile is painted from `FavoritesController`, never from local widget state — the same product appears on several grids at once. A tap **moves the heart first and sends afterwards**, and a refused request puts it back: waiting for a round trip feels broken, and lying is worse.

A guest has nowhere to save to, so the tap opens the sign-in flow and saves the product they were reaching for once an account exists (`toggleFavorite`). The app holds its own list rather than the server marking each product, because a per-caller field would take the browsing reads out of the backend's cache.

### The product card, sections and the basket

`ProductTile` is a white card with the photo on a `photoPanel`-coloured panel, the name (2 lines), `specs` under it (2 lines of its own — the size lives there, so a long name must never squeeze it out), then the price. **One size is one card**; nothing folds rows together. The height is fixed at 230 and every text carries an explicit line height — `screen_chrome_test` checks the worst case at the narrowest width. **The catalogue photos must be shot on `AppColors.photoPanel` (#F4F2EF)**, or `contain` leaves visible bars either side; the token is separate from `background` so the page can be retuned without a reshoot.

`ProductSectionBar` — a pinned «Категории» button plus a chip per `ProductSection` in use — sits over the grid on the shop card and on the owner's «Товары», and is drawn only when a catalogue uses two sections or more. **The button and the chips are one choice made two ways**: the button opens a sheet with the full names and a count each, both write the same selection. The owner's «Добавить товар» is a button pinned to the bottom of the screen (`_AddProductBar`), never a cell at the end of the grid; a spent allowance greys it out and says so on it. `productsBySection` orders «Все товары» by chip, catalogue order inside each, an owner's own rows (no section) last. `templatePricingProgressFor` counts **basket rows only** (`inBasket`), or an owner in the comparison is told they are one price short of it.

### Address search and «О приложении»

Typed suggestions come from Photon, a pin's address and a submitted search from Nominatim (`GeocodingService`) — see the `deployment` skill for why. `AboutScreen` carries the link Yandex's free MapKit licence requires and the OpenStreetMap credit; it is reachable from the guest gate too.

### Images

Product photos come from the api as two ready-made urls — grids load `image_thumb_url`, the edit screen loads `image_url`. **Never build the thumb url in Dart**: an apk that appended `_thumb` itself would freeze the convention inside every build already on a phone.

The VIP carousel and the category tiles are bundled assets (`assets/decorations/{vip,categories}`), not server files: they are the first thing on the home screen and have to be there before the network is.

### Map Mechanics & Pins

The map is strictly rotation-locked and tilt-locked so that teardrop pins and price labels stay upright. Pins are completely withheld below a zoom level of 13 to prevent visual clutter. A map pin conveys two distinct channels of information: the teardrop carries a Lucide glyph for the shop's category, and a separate label carries the price comparison.

### Toolchain & Workflows

Building for Android strictly requires JDK 21+ due to Yandex MapKit's bytecode requirements. We cap the Gradle heap to 4GB in `gradle.properties` to prevent OutOfMemory errors on standard laptops. We use `make dev` for Android testing (which supports the map) and `make desktop` with `DevicePreview` for rapid UI layout testing (which lacks map support but runs faster).
