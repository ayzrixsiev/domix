---
name: frontend
description: >
  Domix's Flutter app under frontend/lib — screens and widgets, the design tokens in
  app_colors.dart and app_theme.dart, ChangeNotifier controllers, the MapKit map and its pins,
  address search, favourites, the Корзина tab, the product card and the home feed, and the Makefile dev loop.
  Use when building or changing UI, laying out a screen, picking a colour or a radius, wiring a
  controller, or working on the map. Not release builds or Gradle (deployment skill).
---

# Domix frontend

## Architecture

Feature-first: `lib/features/<feature>/{data,presentation}`. `ChangeNotifier` view-models provided as
singletons through `MultiProvider`.

- The app ignores the device's font-size setting (`MediaQuery.withNoTextScaling`) and locks to
  portrait, because the UI rests on fixed-height cards that scaled text has nowhere to go in. **If
  cards that size to their content ever land, delete the wrapper rather than raising the constants.**
- Anything belonging to a session is wiped through `AuthController.onSessionEnded` and fetched through
  `onSessionStarted`. **`main()` is the one place allowed to wire both ends** — that is what keeps
  `profile/` from importing `stores/` or `favorites/`.
- **Сообщения is a placeholder.** It stays in the nav bar and says «скоро». Do not rebuild a feature
  into it.
- **The shell names its tabs (`_ShellTab`) and never numbers them**, because Корзина is missing from an
  owner's bar and the same position means a different tab depending on who is signed in. The page list
  stays fixed so the map is never rebuilt. A customer who becomes an owner while on Корзина lands on home.

## Design system

Tokens live in `app_theme.dart` and `app_colors.dart`. Use them; never a literal colour or radius.

- **The look is iOS: a cool off-white page under pure-white cards.** `background` is `#F2F2F6`, iOS's
  own grouped-list grey, so a white card reads as a white *object* rather than as the page. The step is
  deliberately small, so a card without `AppShadows.card` (two layers, cool slate) disappears.
- Brand orange is reserved for primary actions. `trackGrey` is a groove — a step *below* `background`,
  because a track lighter than the page reads as a card sitting on top of it.
- **The header sits flat on the page** (`AppPageHeader`: page colour, no band, no shadow; title 21/w800
  with an optional subtitle). A band of a second colour read as a toolbar bolted onto the screen.
- `CircleIconButton` is a white disc with a shadow and **no ring**. **A disc sharing a line with a
  search field takes that field's height**, never the title's 40 (`CircleIconButton.diameter`,
  `AppPageHeader.customDisc`, and `MapBarButton.size` 50 over the map): a 40 disc beside a 50 capsule
  reads as the smaller, lesser half of its own bar.
- **The bottom nav bar floats** (`FloatingBottomNavBar`): 22dp clear of each edge against the feed's
  16dp gutter, 8dp above the system inset, blurred over the page, with one orange pill sliding under the
  active tab. **It insets itself with `MediaQuery.viewPaddingOf`, not `padding`** — `Scaffold` does not
  inset a custom `bottomNavigationBar`, and `padding` collapses to zero while the keyboard is open,
  dropping the bar into the system buttons for as long as anyone types. Tabs clear it through the
  shell's `bottomInset`, not a constant of their own.
- **Every search field in the app is `PillSearchField`** — a white capsule, a magnifier, a cross once
  there is text. `floating: true` is the form that hovers over the map (hairline, heavier shadow,
  darker glyphs).
- Do not hand-roll back buttons or empty states: `CircleIconButton`/`CircleBackButton` and
  `EmptyStateView`. `PressableScale` rather than ink ripples, which read as nothing on a bordered
  shape. Icons are `flutter_lucide` only.

## Home feed

The home screen invents no fallback data. VIP and «Лучшие предложения» have a fixed number of slots (5
and 15, from the api); **an unsold slot is drawn at full visual strength**, because it is the
advertisement for the placement.

The VIP carousel is one card across the page in an unbounded forward-only `PageView` (Dart's `%` is
Euclidean, so the index maps below the origin too; **guard the empty list — `index % 0` throws**). It
advances on its own every few seconds so every placement is seen by somebody who never touches it, and
a finger on it always outranks the clock.

**The VIP card's photograph is uploaded from the admin panel and never generated**
(`HomeShopPreview.imageThumbUrl`): a placement nobody has photographed draws an empty frame with its
category glyph, because an invented shop front over a real shop's name is the one thing the section that
is *sold* cannot show. The facts run in the order a buyer checks them — who, where, the comparison, then
two figures. **«Рейтинг» has no source in this build** (no reviews table), so a real shop draws
`strings.noFigure` and only an unsold slot shows a number, which is part of what is being sold. The dots
under the strip are what say there are more placements. Distance is deliberately absent: this app asks
for a location for the map and nothing else.

`ProductSuggestionsPanel` is the list of catalogue names under the search field, and it owns
everything that keeps the traffic down: the three-character floor, a 250ms debounce, and every answer
of the session remembered, so a backspace or a corrected letter costs nothing. **An answer is applied
only while the field still holds the query it was asked for**, which is what makes a slow reply
harmless instead of a list contradicting the text above it; a failed one says nothing at all. The
search itself still runs only on the search key or on a tapped name.

## Корзина

`features/waybills`. The tab lists what this customer has sent; `NewWaybillFlow` sends another. Everything
says waybill in code because "basket" is the price index. **A guest fills the form like anybody else and signs
in at «Отправить»**, with every row kept, then the send continues, because they already pressed the button.
Signing in can land on an owner's account, so the role is checked after that step too.

- **Loaded when the tab comes into view (`isActive`), never at sign-in**: an owner's session must not spend
  a refused request on a tab it never shows. Post-frame, because the shell is mid-build at that moment.
- **`WaybillSheet` is the paper form on a phone**: fixed columns and unbroken rules, the same object while it
  is filled in and when it is read back.
- **A refusal clears on `onChanged`, never on a controller listener.** A listener also fires when a field takes
  focus, which is exactly what a refusal does to the field it names: the error would wipe itself in one frame.
- **`_requestId` goes back to null on any edit.** A retried id answers with the list already stored.
- **The picker is called at 2000px**, not the product photo's 1440: somebody reads handwriting off this.
- **`_recoverLostPhoto` answers `retrieveLostData`.** On a phone short of memory Android kills the app while
  the camera is open, and the picture comes back on the next launch through that call or not at all. An owner's
  session skips it, so a lost product photo cannot open a customer's flow.
- The photo is private, so the detail screen fetches bytes through the repository and not `Image.network`.

## Favourites

The heart on a product tile is painted from `FavoritesController`, never from local widget state — the
same product appears on several grids at once. A tap **moves the heart first and sends afterwards**, and
a refused request puts it back: waiting for a round trip feels broken, and lying is worse.

A guest has nowhere to save to, so the tap opens the sign-in flow and saves the product they were
reaching for once an account exists (`toggleFavorite`). **The app holds its own list rather than the
server marking each product**, because a per-caller field would take the browsing reads out of the
backend's cache.

## The product card, sections and the basket

`ProductTile` is a white card: the photo on a `photoPanel` panel, the name (2 lines), `specs` under it
(2 lines of its own — the size lives there, so a long name must never squeeze it out), then the price.
**One size is one card**; nothing folds rows together. The height is fixed (`ProductTile.height`) and
every text carries an explicit line height, so it holds on any font; `screen_chrome_test` checks the
worst case at the narrowest width.

**The catalogue photos are shot on `AppColors.photoPanel`** (`#EFF0F5`, the median edge of the shots,
which range `#E5E8EF`–`#F4F5F7`), or `contain` leaves visible bars either side. The token is separate
from `background` so the page can be retuned without a reshoot.

`CatalogueSearchBar` is the one row over a catalogue grid — on a shop's card and on the owner's «Товары»
alike: the search field and, when the catalogue uses two sections or more, the disc that opens the full
names with a count each. **There are no section chips**: a scrolling strip plus a «Категории» button
under it were the same choice offered twice and cost two rows before the first product. **The field and
the sections are separate questions** — a catalogue too short to be worth searching (`_searchThreshold`)
can still be split, and then the bar is `searchable: false` and draws the button alone.

The owner's «Добавить товар» is pinned to the bottom of the screen (`_AddProductBar`), never a cell at
the end of the grid; a spent allowance greys it out and says so on it. `productsBySection` orders «Все
товары» by section, catalogue order inside each, an owner's own rows (no section) last.
`templatePricingProgressFor` counts **basket rows only** (`inBasket`), or an owner in the comparison is
told they are one price short of it.

## The map

Rotation-locked and tilt-locked, so pins and price labels stay upright — a pin drawn flat on a tilted
plane is unreadable. A shop is a plain `ShopDot` until zoom 13, where it becomes a `ShopPinIcon` — a
drawing of its trade, one bundled file per `ShopCategory` — and a price label joins it at zoom 15.

**The pin's size follows the zoom** (`ShopPinIcon.scaleForZoom`, 0.7 at 13 rising to 1.0 at 15, applied
through `MapPin.scaleWithZoom`). `DomixMap` pushes it to the placemarks on camera frames with
`setIconStyle`, which rescales the bitmap MapKit already holds: no rebuild, no re-rasterization. The
label waits for full scale because MapKit scales the whole marker and the label is 11px type.

**Every pin file carries its point on its bottom row, dead centre**, with its drop shadow and ground
mark baked in above it and nothing below. That row is the coordinate, so the placemark anchors at
(0.5, 1.0) for all four categories and the centred column puts the label over the point.
`map_pin_artwork_test` guards it, along with the other silent failure here: **MapKit rasterizes a pin
once, off-screen, with no second frame**, so an `Image` still decoding caches as blank for the session
— which is why `MapPin.builder` is a `FutureOr` and awaits `ShopPinIcon.decoded`.

## Address search and «О приложении»

**Typed suggestions come from Photon, a pin's address and a submitted search from Nominatim**
(`GeocodingService`): Nominatim's policy forbids as-you-type, and the public Photon instance allows it
but promises no speed, so a typed lookup gives up after a few seconds and the panel asks for «Найти»,
which is the Nominatim path. Operational detail — the measured outage and the fallback options — is in
the `deployment` skill.

`AboutScreen` carries the link Yandex's free MapKit licence requires and the OpenStreetMap credit, and
is reachable from the guest gate too.

## Images

Product photos arrive as two ready-made urls — grids load `image_thumb_url`, the edit screen
`image_url`. **Never build the thumb url in Dart**: an apk that appended `_thumb` itself would freeze
the convention inside every build already on a phone.

The category tiles are bundled assets (`assets/decorations/categories`), not server files: they are the
first thing on the home screen and have to be there before the network is.

## Toolchain

- `make dev` runs on Android (pinned on purpose — the desktop has no MapKit, and silently running the
  one build that cannot show the map is worse than refusing). `make desktop` is faster for layout work.
  `make check` is analyze + test.
- **Android needs JDK 21+** (MapKit's bytecode) and Gradle's heap is capped in
  `android/gradle.properties`, sized to this machine — the Flutter template's `-Xmx8G` let one build ask
  for more memory than the laptop had. **If a release build dies with OutOfMemoryError, close the
  emulator before raising anything**: R8 is the hungriest step and only runs for release.
  `make gradle-stop` reclaims the daemon's heap.
- **`DevicePreview` is development-only and has been removed and restored twice. Leave it.** The
  emulator is a real phone running a *debug* build, which interprets Dart rather than running compiled
  code, so scrolling stutters there and it is the wrong place to judge a layout. `enabled:
  !kReleaseMode && !MapConfig.isSupportedPlatform` scopes it to desktop. The wrapper order is
  load-bearing: `DevicePreview.appBuilder` supplies the simulated phone's `MediaQuery` and
  `withNoTextScaling` sits inside it so ours wins — **delete the DevicePreview half before release, not
  that one.**
