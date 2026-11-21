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
- **A failed read keeps its kind, never a bool.** A repository throws `ApiException(status)` for any
  refusal, `LoadFailure.of` sorts it into network, busy (429/503) or server, and the screen picks its
  sentence with `loadErrorHintFor`. **«Проверьте подключение» is only ever the network case**: under a
  500 it sends somebody off to fix a phone that works. Home, the map, a shop's catalogue, «Мои
  магазины», favourites, Корзина and the add-store and send errors all follow it, and
  `failure_copy_test` holds every one of those sentences to it. A new loader that throws a plain
  `Exception` lands in "server" whatever happened.
- **The shell's page list is fixed** (`_ShellTab`, one bar for every role) so the map is never rebuilt.
  Корзина is on everybody's bar, owners included.

## Signing in

`OnboardingFlow`: **Язык → Политика → Имя и роль → «Зарегистрироваться через Telegram»**, one route
with an X, and one button for registering and signing in because the server finds or creates the
account either way. The bot hands over a number and nothing else, which is why the name and role are
asked first and ride in the session (`AuthService.startTelegramSignIn`).

- **Polling, not a deep link back.** The flow opens the t.me link with `launchUrl(externalApplication)`
  — **its return value is the signal, never `canLaunchUrl`**, which lies on Android 11+ without the
  manifest's `<queries>` — then asks `/api/auth/status` every two seconds and **at once on `resumed`**,
  since the reader is in Telegram and Android holds a background app's timers back. It stops at
  `expires_in` with «Время вышло».
- **A finished login is handed out once**, so `pollTelegramSignIn` saves the session before it returns:
  dropping that answer would leave a signed-in account looking like a guest with no second read.
- **A `success` closes the flow even after «Отменить»**: the account is signed in on the phone by then.
- Telegram being absent needs no handling — everyone in Uzbekistan has it; a link that does not open
  says «Не удалось открыть Telegram» and the button opens it again.
- **«Войти по номеру телефона» is a door off the last step, never a step** (`PhoneSignInFlow`): two
  more steps in `_Step` would tell every telegram user they are on step four of six. **The two ways in
  are one choice and are drawn as one**: two `AppWideButton`s of the same width stacked in the step's
  content, Telegram first, and that step's `FlowFooter` has no primary button, only «Назад» in the place
  it holds on every step (`onboarding_flow_test` measures both). The phone route is its own full-screen
  route: the number, then the code, with «Изменить номер» as the step back. The name and role ride
  into `requestCode` as they ride into the telegram session, and `verifyCode` lands through the same
  `_saveSignIn` and `_applyAccount` as a telegram `success`. Until Gateway is paid only the Play
  review account gets a code; **`sms_unavailable` is drawn as an `AppNoteLine`, never as an error**,
  because nothing the reader typed is wrong.
- **The number cannot be edited.** `ProfileEditScreen` is the name and the role; the number is the one
  Telegram proved, and a different number is a different account.

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

`features/waybills`. The tab lists what this account has sent; `NewWaybillFlow` sends another. Everything
says waybill in code because "basket" is the price index. **Every role uses it**, shop owners included.
**A guest fills the form like anybody else and signs in at «Отправить»**, with every row kept, then the send
continues, because they already pressed the button.

- **Loaded when the tab comes into view (`isActive`), never at sign-in**: most sessions never open it.
  Post-frame, because the shell is mid-build at that moment.
- **`WaybillSheet` is the paper form on a phone**: fixed columns and unbroken rules, the same object while it
  is filled in and when it is read back.
- **A refusal clears on `onChanged`, never on a controller listener.** A listener also fires when a field takes
  focus, which is exactly what a refusal does to the field it names: the error would wipe itself in one frame.
- **`_requestId` goes back to null on any edit.** A retried id answers with the list already stored.
- **The picker is called at 2000px**, not the product photo's 1440: somebody reads handwriting off this.
- **`_recoverLostPhoto` answers `retrieveLostData`.** On a phone short of memory Android kills the app while
  the camera is open, and the picture comes back on the next launch through that call or not at all. **The
  call answers for every picker**, and an owner photographs products too, so it opens the flow only when
  `WaybillPhotoMarker` says the waybill picker was the one open.
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

**A shop owner sees no other shop's prices or index** (backend skill). The server decides; the app
only obeys: `Product.priceHidden` draws «Цена скрыта» on the tile and counts as a priced row on the
card, with one `AppNoteLine` above the grid, and `HomeContent.indexHidden` replaces «Лучшие
предложения» with a note. The map, home, a shop and its catalogue go out with `AuthService.viewerHeaders`.
**`AuthController.onViewerChanged` fires on sign-in, sign-out and a role change**, and `main()` re-reads
home and the map at once and marks every cached catalogue stale: the shell keeps those tabs alive, so
nothing else would ask again.

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

**The map on screen is one frame behind the map MapKit drew.** A pin change on a still camera costs
one frame, so it stayed unseen until a finger moved the map: a category filter, an empty category
most of all. `DomixMap._flushFrame` steps the camera a centimetre aside and back once the pins settle,
and again when a first-time raster lands. It is a workaround for the plugin's texture view, measured on
one phone; **do not replace it with `map.move(map.cameraPosition)`, which draws nothing**, and delete it
if a plugin upgrade makes a filter apply without it.

## Address search and «О приложении»

**Every lookup goes to our `/api/geo/*`, never to Yandex** (`GeocodingService`): the keys stay on the
server, which caches for everybody and holds the one daily budget all copies of the app share. Typing
asks for suggestions, the search key for geocoder results, and **a suggestion has no point until it is
tapped** — `resolve` is one more lookup, so it is made only for the line actually picked. The panel's
floor, debounce and session cache are what keep that budget alive; a failure says «Проверьте
подключение» only when it really was the network (`LoadFailure`), and a budget spent or Yandex down
says «Поиск адресов сейчас недоступен». The token goes along when there is one, so a signed-in caller
is metered by account.

**The location picker's field is the map's panel**, `MapSearchPanel.addresses`: the same debounce, floor
and dropdown with no shops, and nothing drawn under three letters. Do not give the picker a list of its
own again. The address it returns, which is what a shop stores, is the server's short form (below).

`AboutScreen` carries the two links Yandex's free terms require — `maps_api` and, under the terms' own
wording «Условия использования сервиса Яндекс.Карты», `maps_termsofuse` — and is reachable from the
guest gate too.

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
