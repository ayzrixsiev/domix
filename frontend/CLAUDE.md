# Frontend (Flutter)

Loads when working under `frontend/`. Product rules, the Basket Price Index, the schema and the
cross-stack traps live in the repo-root `CLAUDE.md`; release and Android-build material lives in the
`shipping-to-play` skill.

---

## 1. Commands

```bash
make setup      # write a starter env.json if missing, then flutter pub get
make emulator   # boot the domix AVD, leave it running
make dev        # run on the Android emulator
make dev-skia   # same on the old renderer — a diagnostic for emulator stutter, not a workflow
make desktop    # run on Linux instead — faster, but has no map
make check      # flutter analyze && flutter test
make apk-test   # RELEASE build against env.json — what to sideload before a domain exists
make release    # guard-jdk + guard-prod + check, then the .aab against env.prod.json
```

**`dev` is pinned to Android and `desktop` is a separate target on purpose.** Left alone `flutter run`
takes whichever single device it can see, which here is the Linux desktop — and MapKit does not exist
there, so it would silently run the one build that cannot show the map. Both targets are supported;
desktop is genuinely faster for the home screen and the forms.

> `flutter run -d <x>` matches a device's **id or name, never its target platform**, so `-d android`
> matches nothing even with the emulator up — and the error prints `android-x64` in the platform
> column, which reads like the very thing that was asked for. `dev` resolves the id
> (`emulator-5554`) out of `flutter devices --machine` with `jq`.

The Makefile exists so `--dart-define-from-file` is not typed by hand and so `dev` and `release`
cannot be pointed at each other's env file. `env.json` supplies `API_BASE_URL` via
`String.fromEnvironment`; it is **gitignored and per-developer** (it points at that machine's ngrok
tunnel) and `make setup` writes a starter one inline. **There is no `env.example.json`** — a two-key
file did not earn a fourth copy of the same two keys, and a template nobody edits drifts out of date
without anything noticing. `env.prod.json` is the committed reference for the shape.

> `--dart-define` values are compiled in as plain constants and are **recoverable from a shipped
> APK**. Never put a secret in one.

`test/fixtures/api_home_response.json` is **captured from a running backend**
(`curl -s localhost:8080/api/home > …`), not hand-written — a hand-typed fixture tests what its author
believed the backend sends, and that belief is the thing most likely to be wrong.

## 2. Toolchain

**Building for Android needs JDK 21+** — MapKit's plugin ships Java 21 bytecode, and javac 17 fails
with `class file has wrong version 65.0, should be 61.0`, naming neither Java nor the JDK.

```bash
sudo pacman -S jdk21-openjdk
flutter config --jdk-dir /usr/lib/jvm/java-21-openjdk
```

**Set `--jdk-dir` only after the JDK is installed** — pointing it at a missing path takes the whole
Android toolchain down and every build fails with a bare `Error: Build process failed`.
`flutter config --jdk-dir=` (empty) undoes it.

`make guard-jdk` (`tool/check-jdk.sh`) runs ahead of `dev`, `apk` and `release`, and **resolves the JDK
the way Flutter does, not the way the shell does**: `archlinux-java` still has `java` on PATH as 17
while `--jdk-dir` points at 21, so a naive `java -version` check reports 17 and blocks a working build.
Order: `--jdk-dir`, then `JAVA_HOME`, then PATH.

**Gradle's heap is capped in `android/gradle.properties`, sized to the machine** — **4 GB** for a 16 GB
laptop. The Flutter template ships `-Xmx8G -XX:MaxMetaspaceSize=4G`, which on the previous 7.4 GB
machine let one build ask for more memory than the computer had (the JVM grows until it hits the
ceiling, not until it is done), so the desktop froze mid-build and the OOM killer took whatever it
reached. The file also caps the *Kotlin* daemon — a second JVM the first setting does not govern — and
`org.gradle.workers.max`. **If a `--release` build dies with OutOfMemoryError, close the emulator
before raising anything**: R8 is the hungriest step, it only runs for release, and the AVD holds 4 GB.
`make gradle-stop` reclaims the daemon's heap.

## 3. The emulator

**Any screen with a map needs a device or an emulator** — MapKit is Android/iOS only, so a desktop run
shows `MapUnavailablePanel`. A `domix` AVD (Android 35, Google APIs, Pixel 7, x86_64) is set up:
`flutter emulators --launch domix`.

**MapKit cannot draw without a GPU** — it is a native OpenGL renderer, and the AVD shipped with
`hw.gpu.enabled=no`, which presents as a blank map and is indistinguishable on sight from a bad API
key. `~/.android/avd/domix.avd/config.ini` now carries `hw.gpu.enabled=yes`, `hw.gpu.mode=host`,
`hw.ramSize=4096`, `vm.heapSize=512`. **`config.ini` is read at launch, so a change needs a cold
boot**: `flutter emulators --launch domix --cold-boot`. A working GPU announces itself in logcat as
`yandex.maps: Chosen EGL config={r=8, g=8, b=8, ...}`.

The AVD has **no Play Store** (Google APIs image), so Telegram — which login goes through — must be
sideloaded once; it persists across restarts:

```bash
curl -L -o /tmp/telegram.apk https://telegram.org/dl/android/apk && adb install /tmp/telegram.apk
```

There is **no device skin installed** (skins ship with Android Studio, not the CLI SDK), so the
emulator window is a bare rectangle — cosmetic, but it is why `DevicePreview` was restored (§10).

> If `flutter emulators` reports none while `~/.config/.android/avd` has some, symlink it:
> `ln -s ~/.config/.android/avd ~/.android/avd`.

---

## 4. Layout

Feature-first: `lib/features/<feature>/{data,presentation}`.

- **`data/`** — repositories and services doing network or storage I/O.
- **`presentation/controllers/`** — `ChangeNotifier` view-models consumed via `provider`, built once in
  `main.dart` and handed to `MultiProvider` as singletons. Controllers needing I/O before first paint
  are awaited above `runApp` and passed with `.value`; the rest use `create:` so provider builds them
  lazily. `AuthController` additionally enforces its singleton with a private static-instance
  constructor, since non-widget code references it directly.
- **`presentation/screens/`** and **`widgets/`** — UI.

Bottom navigation: Home / **Заявки** / Map / Сообщения / Profile. Заявки is the job-ticket
placeholder; it took the Search tab's slot because search now lives on the map and the home header
(`features/search/` was deleted with that change — `git log` has it).

Localization is custom, not gen-l10n: `core/localization/app_localizations.dart` plus
`language_provider.dart`, a `ChangeNotifier` holding the current `AppLanguage`. Locales are `ru`/`uz`.

`AuthService` implements exponential backoff with jitter (`_executeWithRetry`) — reuse that rather than
adding ad-hoc retry logic. `core/constants/api_config.dart` (`ApiConfig.serverRoot`) derives the plain
server root from the same `API_BASE_URL`; anything that isn't an auth call builds its URL off that.

---

## 5. Home screen

`GET /api/home` returns the VIP carousel and the tabbed best offers together — one round trip, one
spinner, one error state instead of three that can disagree.

`home_screen.dart` puts **no horizontal padding on its scroll view** — each block applies the shared
`_gutter` (16px) itself, which keeps headings aligned with the DOMIX pill while letting
`VipShopsCarousel` bleed to the edges. **Sections are separated by whitespace alone (26px) — no
section containers anywhere on the feed.**

### Slots: both shop sections are a fixed number of places

**Nothing on this screen is invented.** `home_showcase_content.dart` and its `kShowcaseFallbackEnabled`
flag are deleted; `HomeController` has no substitution left in it. What the sections draw instead is a
fixed number of *slots* — 5 in the carousel, 15 per Лучшие предложения tab — filled by real shops and
otherwise drawn empty. Root §7 has the product reasoning and the server's half.

`vipSlotRing` and `rankedSlots` (`features/home/data/home_content.dart`) decide which slot a shop
lands in. They are in the data layer on purpose: **where a paying shop appears is a product rule, and a
rule wants a test that does not need a screen to run** (`test/home_content_test.dart`).

- **The ring fills centre-outwards** — 0, +1, −1, +2, −2 — because the carousel opens parked on the
  middle slot. With one placement sold, that shop is the card on screen, not two swipes past empty
  ones. Positions are taken `% size`, which is what lets an offset walk off the end of an even-sized
  ring instead of throwing.
- **`rankedSlots` fills in order**, because that section is a ranking and the reader starts at the top.
- **Neither truncates**: both size to `max(slotCount, shops.length)`, so a server that grew a section
  costs an old build an extra card rather than hiding a placement somebody paid for.

**An empty slot is drawn at full strength — the same surface, shadow and branded banner a real card
gets — and only its *text* differs.** A recessed treatment was tried first (page-coloured fill,
`trackGrey` outline, no shadow, on the reasoning that a well cut into the page reads as "empty" before
a word of it does) and rejected on sight: this is the section the eye lands on first, and four faded
frames around one real card made the whole strip look broken rather than look available. **An unsold
slot is a product being advertised, and an advertisement has to be as handsome as the thing it sells.**

So the carousel's two cards share `_cardSurface` and `_Banner` *literally* — one `const` decoration
and one widget, because the moment they are two, one grows a different shadow. `EmptyShopRow` matches
`HomeShopRow` the same way. The accepted cost: a real row and an open one are alike at a glance, and
what tells them apart is reading «Название магазина».

The labels are field *names* — «Адрес», not «Здесь будет адрес» — and no name, street, amount or
percentage appears anywhere in one. The single exception is `kSlotRating` (`'5'`), which lives in
`home_content.dart` because both widgets draw it and two copies of one number can disagree.

### VIP carousel

Shops with a live placement, **left**-joined to the index — a placement appears the moment it is
granted, price or no price, because the alternative is somebody paying and seeing nothing (root §7).
So a VIP card can legitimately show no basket and no badge. VIP shops are **not** excluded from best
offers: VIP is a placement tier, not a separate catalogue, so one that is genuinely cheap earns a row
on merit.

A page-snapping loop that never ends in either direction: `PageView.builder` with a null `itemCount`
is unbounded *forwards only*, so it opens at page `5000 × slots.length + slots.length ~/ 2` and maps
the index with `%` (Euclidean in Dart, so it holds below the origin too). **Guard the empty list —
`index % 0` throws.** The `+ length ~/ 2` is what parks it on the centre slot.

**The `initialPage` trap is designed out now, not worked around.** A `PageController`'s `initialPage`
cannot change after it is built, and the opening page used to depend on a shop count that lands after
the first frame — hence the `ValueKey` forcing a fresh `State`. The slot count is a constant, so the
opening page is one too. The key stays, on `slots.length`, only for the case where a backend sends more
placements than this build expects and the ring grows.

#### Card size: `viewportFraction`, `cardGap` and `_offCentreScaleDrop` are **one dial**

How much of the next card a reader sees is

```
W × (1 − viewportFraction) / 2   −   cardGap   −   (viewportFraction × W × scaleDrop) / 2
```

and that sliver is the only thing saying "there are more of these" — a full page of tiles leaves no
other edge showing. **Widening the card takes from it, and so does deepening the recede.**

Today: `0.87 / 4 / 0.04`, giving `23.4 − 4 − 6.3 ≈ 13dp` on a 360dp phone. That is *the same peek* the
previous `0.84 / 5 / 0.07` gave — the card was widened by ~13dp and paid for out of the recede, which
is now subtle. `cardHeight` went 232 → 252 with it (banner 120 → 132).

**`test/home_screen_test.dart` measures this at 360dp** rather than at the 800dp test default, so the
next person to widen the card finds out from a failing test instead of from a phone. Wanting the
recede back means narrowing the card again; there is nowhere else to find the pixels.

**An off-centre card recedes 7%, and the number is capped by `viewportFraction` (0.84).** A card scales
about its own centre, so every point of shrink eats the neighbour's visible sliver — ~16px of peek at
5%, ~6px at 12% on a 360dp phone. **"Stronger effect" and "leave an edge of the neighbours visible"
are the same dial pulled opposite ways**; 12% was tried and reverted. Wanting more means bringing
`viewportFraction` down with it (0.80 buys back what 12% costs) and a narrower card everywhere.

**A card opens `ShopCardScreen`** (§7) — through `PressableScale`, not an ink ripple, whose
`onTapCancel` also matters here specifically: the `PageView` claims the gesture the moment a swipe
starts, and without it a card would stay shrunk after every failed tap.

The card puts the **shop's name on the cover image in brand orange**, opposite the rating badge; a dark
scrim behind it was tried and removed, since over a pale peach placeholder there is nothing to protect
text from. Below the image: address, basket price as the largest element, then the badge — fixed gaps
rather than `spaceBetween`, so the rhythm is identical on every card. **A `Column` in a fixed-height
card fails by overflowing, not scrolling** — silent in release, so adding a line means raising
`cardHeight`.

### Лучшие предложения

Cheapest shops, **one segment per shop category**. A comparison only means something inside a category:
a Сантехника basket is a different list of goods from a Универсальный one, so "на 4% дешевле рынка"
refers to a different market on each row, and stacking them in one column would invite comparing 4%
against 6% when the two are measured off different baselines. All groups arrive in one response
(bounded at 4 × 15), so switching is never a request. **Only categories with ranked shops become
segments**, and with one populated category the control is not drawn at all rather than showing a
single permanently-selected pill. It is **not** a proximity list — there is no location input, which
is why the rows show no distance. **A row opens `ShopCardScreen`** (§7); `HomeShopRow` takes a plain
`VoidCallback?` and the screen builds the closure, so navigation stays out of the leaf widget.

**Each tab is `BestOffersList.slotCount` (15) places**, real shops first and `EmptyShopRow` for the
rest.

**With *no* category ranked — where the app launches — the section still draws its fifteen places,
with no tab strip.** It used to disappear entirely, which read as a screen missing a chunk of itself.
There is no strip because the tabs come from the data and there is none; that is a different thing
from "a tab set to no category", which would be a filter that filters to nothing. `groups.isEmpty` is
handled in `BestOffersList.build`, not by the screen, so the screen renders the section
unconditionally.

The filter is an **iOS-style segmented control**: a recessed `trackGrey` track with a white pill
sliding over `AppMotion.base`. **Every segment is exactly the same width**, taken from the container and
not the text — "Универсальный" is eleven characters and "Обои" four, so content-sizing would stop them
reading as peers; long labels ellipse, and past four segments the track scrolls. The pill sits *behind*
the labels so the transition reads as one object sliding, and no segment paints its own background (one
that did would double up mid-transition and flash). A `TabBar` is the wrong shape — underline indicator,
its own typography, tabs sized to their labels.

### Популярные категории

Twelve tiles off the same `ProductCategory` enum the backend stores, with labels and glyphs hanging off
exhaustive `switch`es — so a thirteenth category is a compile error rather than a blank tile.

- **A two-page pager, not a three-row grid, and no "Все →"** — the pager *is* the control that reveals
  the rest. **No shop counts** either: a tile is a way in, not a statistic.
- **No white surface, behind the section or a tile** — a white card holding a framed glyph box is two
  borders per tile, twelve times over.
- **The glyph box is `trackGrey`, not `cardGrey`.** `cardGrey` (`#F1F3F6`) is *lighter* than the page
  (`#EFF1F5`), so with no panel behind them the tiles read as white. **A fill is grey relative to what
  is behind it, so moving a surface out from under a widget can silently invert what its fill means.**
  No border — `hairline` is lighter than `trackGrey` and would ring a darker fill in a paler line.
- **The label is top-aligned under the glyph box, not centred in the cell.** Centring drops the box
  half a line on whichever tiles wrap to two lines, so a row of four gets its icons at two heights —
  and which tiles wrap changes with the display language. `Expanded` round the `Text` gives it a tight
  height, and a paragraph in a tight box paints from the top.
- **The pager's inactive dot has to be visible or the second page does not exist** — it was `hairline`
  on `background` at ~1.02:1, so the section read as one page of eight. `textFaint` now, and the
  **only** affordance for page two.
- **Cells are sized with `mainAxisExtent`, not `childAspectRatio`**, which derives height from width and
  made cells grow on wide phones.
- `_PageDots` rebuilds off the `PageController` as a `Listenable`, not `onPageChanged` — that fires
  once, *after* the snap, so the indicator lags the finger. Guard `hasClients && page != null`; both are
  false on the first frame.

**Tapping a tile opens `CategoryProductsScreen`** — every priced product in that category across every
shop, cheapest first, through the same `ProductGrid`/`ProductTile` the owner's catalogue and the map's
shop card use. Each tile carries its shop's name as a subtitle, because a price with no seller
attached is not actionable.

### There is no fallback content, and there must not be one again

`home_showcase_content.dart` held invented shops so a fresh install would demo, substituted by
`HomeController` whenever the backend came back empty *or unreachable*. **It is deleted, with its flag,
its `if`, and the showcase branches in `productsForCategory` and `searchProducts`.** `HomeShopPreview`
lost its bare constructor with it — every preview now comes from a real `Shop`, which is what removed
the "this card is inert" branch from three widgets.

What replaced it, and the distinction worth holding on to:

- **A VIP or Лучшие предложения slot is drawn empty**, because those sections are a fixed number of
  places and an unsold one is a real thing to say. It shows field names, never a plausible shop.
- **A category tile with no products opens onto an empty state**, not a grid of boxes. The difference
  is intentional: a slot is inventory, an empty category is just empty and should say so.
- **There is deliberately no «Пока нет магазинов» block on the feed any more.** It belonged there while
  an empty feed meant empty *sections*; once both sections started drawing their open places, a
  screenful of designed-empty cards followed by a notice explaining that it is empty said the same
  thing twice — and the second time it read as something being wrong. `noShopsYetHint` went with it;
  `noShopsYet` stays for the map, where no pins really does look like a failure.
- **A failed load still says so**, in `homeLoadError` with a retry, danger-coloured, *below* the
  sections rather than instead of them — the five slots and twelve tiles are the shape of the screen,
  not data that came back wrong. That is the one thing the open places cannot explain by themselves.
  And the sections are **emptied** on failure, never left showing the last successful load under a
  banner: this is the list a customer decides where to drive from.

### Search

**Search is its own screen, and the bar on the feed is a button that opens it.**
`GET /api/products/search?q=` returns the same shape `/api/categories/{code}/products` does, so both
render through `ProductResultsView` — one widget owning the loading, error, empty and grid states,
wrapped by `ProductResultsScreen` (a title) or the search screen (a field). That sharing is the point:
a second grid would be a second set of states to get right, and the `RefreshIndicator` trap (root §8)
to fall into twice. **The bar became a button because an inline field trapped the keyboard** — this is
*not* a return to the styled-`Text` version; it does exactly what it looks like it does.

- **A new query is a new `Key`, not a mutation.** `ProductResultsView` fetches once from its own
  `initState`; re-running means `ValueKey(query)` so Flutter builds a fresh State, where swapping the
  query on the live one would race the new request against the one in flight.
- **Results stay put while the field is being edited**, and clearing it returns to the prompt.
- **As-you-type is deliberately not built** — `onSubmitted`, not a debounced `onChanged`, because every
  keystroke past two characters is a sequential scan (root §7). The app enforces the two-rune floor
  before navigating (`SearchResultsScreen.isSearchable`); the server's check is the backstop.
- **The filter button was deleted, not disabled** — it was a `Container` with `onTap: () {}`.

### Header

All controls are real (`home_header.dart`), where they were once non-interactive `Container`s that
looked like buttons. The **city pill** opens the same `LocationPickerScreen` the add-store form uses
and keeps only the city; `CityController` ignores a blank city and a case-insensitive match, so moving
the pin within one city rebuilds nothing. The **bell** opens a permanently-empty notifications screen,
because an icon that does nothing reads as broken where an empty state reads as "nothing yet". Known
wart: once picked, the city pill stops following the app language until it is re-picked.

---

## 6. Map (`features/map/`)

- **Both maps are rotation-locked** — `rotateGesturesEnabled = false` plus `tiltGesturesEnabled =
  false`, set once in `DomixMap`. A two-finger twist would leave every teardrop pin on its side with
  its price label upside down. Pan/zoom/fling are untouched.
- **The map is deliberately not inside a `SafeArea`** — a map is a canvas and must run edge to edge
  under the notch; only the overlay controls are wrapped. Same reason it sets
  `AnnotatedRegion<SystemUiOverlayStyle>` dark.
- **Attribution is MapKit's, not ours.** The hand-rolled OSM pill is deleted.
- Camera moves go through `_flyTo` → `DomixMapController.flyTo`, one native call.

### The zoom threshold

**Pins are withheld below `MapScreen._minShopZoom` (13), and the map opens at 12** — so it opens with
no pins and a "Приблизьте карту · 47 магазинов" line, and one pinch brings them in. The threshold is
deliberately *above* the initial zoom; equal to it, the rule would only fire on the way out.

- **Off-screen culling is not ours and must not be reimplemented** — MapKit culls natively, and what
  culling cannot help with is the case the threshold exists for: zoomed out over a city, *every* shop is
  inside the viewport.
- **The state is a bool, not the camera.** The camera listener fires every frame of a pinch, so holding
  the zoom in state would rebuild the pin list at 60fps; `_onZoomChanged` only calls `setState` when
  `zoom >= _minShopZoom` flips.
- Search reaches any shop from any zoom: picking a result flies to `_focusedZoom` (16), which trips the
  threshold on its own because MapKit reports programmatic moves through the same listener.
- `test/map_zoom_test.dart` pins it against *both* silent failures — a threshold below the initial zoom
  (never fires) and one above any reachable zoom (permanently empty). It asserts on **`DomixMap.pins`,
  not `ShopMarker` widgets**: pins are rasterized off-screen, so `find.byType(ShopMarker)` finds nothing
  at any zoom and would pass and fail for the wrong reasons.

### Pins

**A pin says two independent things in two channels.** The teardrop stays brand orange and carries a
glyph for the *shop category* (`ShopCategory.icon`), so forty identical markers become four readable
groups; the label above it carries the *price comparison* only, as `PriceTierPinLabel`. Conflating them
— colouring the pin by tier — was rejected: category is always known and tier usually is not, so the
pin would have three price colours plus a fourth "no data" colour and the category would have nowhere
left to live.

**The current set is the founder's pick (2026-08-18) and must not be changed without asking:**
универсальный `wrench`, сантехника `bath`, древесные материалы `tree_pine`, обои `paint_roller`. The
thread through it is *name the material the shop sells, not something adjacent*. **Not `hard_hat`** for
универсальный — the Заявки tab wears that one, and a glyph must not mean "workers" in the nav and
"магазин" on the map.

**Pick map glyphs by rendering them, not by their names** — Lucide's names lie often enough that three
of four were wrong on the first pick (`wallpaper` is a desktop background; `logs` is a log *file*, so
the family has no timber glyph at all). Render the codepoint out of
`~/.pub-cache/.../flutter_lucide-*/lib/fonts/lucide.ttf` with ImageMagick, **onto the orange circle at
22px**, since the question is what survives at pin size.

**Known cost, accepted:** three of four share a glyph with a home-screen `ProductCategory` tile. The two
lists mean different things (a kind of *shop* against a kind of *product*) and never share a surface.

**`MapPinIcon`'s `category` is nullable, and the null case is a plain капля** — the teardrop with a
white hole, the mark every map app uses for "this exact point". It drew `building_2` until 2026-08-18,
wrong twice: the picker points at wherever the user dragged to, not at a building, and a glyph made its
pin read as a fifth shop category.

**The teardrop's triangle meets the circle at its tangent points.** With the base at a fixed fraction of
the width the sides crossed at an angle and the join pinched to nothing, so at 48px the tip read as a
triangle floating below a ball. `_PinPainter` solves for where a line from the tip grazes the circle
(`x = cx ± r·√(1 − r²/d²)`, `y = cy + r²/d`) and unions the paths, so the rim traces one silhouette. The
tip stays at bottom centre, which is what `IconStyle.anchor` 0.5/1.0 assumes.

**The basket price in сум is not on the map** — forty seven-digit numbers competed for a few hundred
pixels, none labelled. It moved into the shop's sheet (`_BasketPriceBlock`); the pin kept what is
scannable at that size, a coloured dot and `−4%`.

### Opening a shop, and search

**Tapping a pin pushes `ShopCardScreen` (§7).** It used to open a modal sheet built inside
`map_screen.dart`, which meant the map owned a screen three other surfaces needed — a VIP card and a
Лучшие предложения row could not open a shop at all. The sheet and its section widgets are **deleted**,
not moved: `_ShopDetailsSheet`, `_ShopMetaLine`, `_BasketPriceBlock`, `_DetailRow`, `_CallButton`,
`_SheetGrabber`, `ShopBanner` and the rest live on only in `git log`.

Picking a search result flies the camera *before* pushing, so popping the card lands on a map already
centred on the shop that was chosen.

`map_search_panel.dart` searches two sources and labels them separately — shops matched
**synchronously in memory** from the loaded list, addresses through Nominatim (debounced 450ms, 3+
chars, to stay inside its ~1 req/sec policy). Result rows use `InkWell(canRequestFocus: false)`;
otherwise tapping one pulls focus off the field and hides the panel before the tap lands.

`location_picker_screen.dart` uses "move the map, not the pin" (a fixed overlay at the screen centre,
not a map object) and reverse-geocodes the centre 700ms after the map stops.

`geocoding_service.dart` — free Nominatim, ~1 req/sec. Use `reverseGeocodeDetailed` when a **city** is
needed: `display_name` cannot be split reliably (a district containing a comma breaks it). OSM has no
single "city" tag, so `_citySearchOrder` tries `city → town → village → municipality → county → state`.
`accept-language` means the city arrives already translated.

---

## 7. Shops (`features/stores/`)

### The shop card

**`ShopCardScreen` is where every route into a shop ends** — a pin on the map, a card in the VIP
carousel, a row in Лучшие предложения. Before it existed only the map could open a shop, as a modal
sheet built inside `map_screen.dart`, so a paid VIP placement was a card that did nothing when it was
tapped: a failure with no error anywhere, on the one card somebody had paid for.

**It takes a whole `Shop`, never an id to look up.** Every entry point already holds one: the map has
the list it drew its pins from, and `GET /api/home` sends full shop rows that `HomeShopPreview` merely
projects down for the feed. So the card paints complete on its first frame — no spinner, no second
round trip for facts the app already had. That is why `HomeShopPreview` now carries the row it came
from, and why that field is **nullable**: `home_showcase_content.dart` invents its rows, there is no
shop behind them, and a `const` preview cannot produce one. A showcase card is therefore simply inert
rather than opening a card about a business that does not exist. `test/shop_card_test.dart` pins all
three cases.

**A pushed route rather than a bottom sheet**, for three reasons in order of weight: it is reached
from lists now, and a list opening a modal sheet on top of itself is not a pattern used anywhere else
here; it can be a `CustomScrollView`, which is what makes the catalogue a **sliver** and kills the
second copy of the `shrinkWrap` bug (root §8); and a sheet's height is a compromise between covering
the map and having room, where a route has the screen. The cost is real and accepted: from the map a
tap now replaces the map, so comparing three nearby shops is three pushes and three pops. Back returns
to the same camera.

Laid out as **white cards on the grey page** rather than one flat surface with hairline dividers:
identity → basket price → the two actions → contacts → catalogue. Notes worth keeping:

- **No cover band.** The obvious marketplace layout opens with a full-width hero image, and nothing
  writes `shops.image_url` — so it would be 200px of placeholder on every shop in the market, which is
  the exact mistake the old sheet's saturated orange banner was. The shop's photo goes in the 52px
  category tile when there is one.
- The **category glyph is the pin's own** (`ShopCategory.icon`) and the line under the name says in
  words what it meant. Someone arriving from the map has just tapped a teardrop with a wrench in it;
  this is the only place in the app that translates it.
- **Позвонить is filled and Маршрут is outlined** — they are not peers. The route link is an ordinary
  `https://yandex.uz/maps/?rtext=~lat,lng` url, so Yandex Maps claims it as an App Link when installed
  and a browser answers when it is not, and it needs no new `<queries>` entry.
- **`launchUrl`'s return value is the signal, never `canLaunchUrl`** — root §8.
- Pull-to-refresh re-reads the catalogue, the only thing on the screen that changes while it is open.

`stores_repository.dart` talks to the real backend. On create, the new `Shop` is appended directly to
`StoresController`'s in-memory list so it appears on the map immediately.
`StoresController.updateShop`/`deleteShop` write through to **both** `_myShops` and `_stores`, so the
map pin moves or disappears at the same moment the management row does — and `updateShop` merges the
known `productCount` back in via `copyWith`, because `PUT /api/shops/{id}` doesn't return it.

`data/shop_category.dart` mirrors the backend's four codes. **`templateSize` (99/50/10/10) is knowingly
duplicated from `internal/catalog`** and must be edited by hand when a template's size changes, with
nothing to catch it — it is shown only *before* the shop exists, so there is nothing to fetch it from.
`fromCode` defaults an unknown code to `universal`, right for a single row; `tryFromCode` returns null
for the one caller where guessing would be worse — the best-offer tabs, where defaulting would merge a
fifth category's shops into Универсальный.

The category picker is `StoreCategoryTile` + `ShopCategorySheet`, shaped like `StoreLocationTile`
rather than a Material `DropdownButton`, which has no room for the per-category description and
catalogue size. **There is no edit-form counterpart on purpose** — category is fixed at creation.

**The per-shop management flow is a hub, not one page.** `MyShopsScreen` → `ShopSettingsScreen` →
`ShopProductsScreen` ("Товары") or `EditStoreScreen` ("Данные магазина", including delete). Managing a
catalogue and "rename or destroy this shop" are unrelated, and a destructive action sharing a scroll
view with a routine one is how a shop gets deleted by accident. **A new per-shop feature should become
a third section**, not more controls on an existing screen.

There was a third row, "Загрузка из Excel", and it is **deleted** — screen, repository method,
controller state, localization, `file_picker`, and the backend endpoint. It wrote `template_key IS
NULL` rows, so an upload of 50 put a shop past the 20-own-products cap: the literal cause of "30 из 20".

`EditStoreScreen` pops `true` on delete and `ShopSettingsScreen` pops itself on seeing that, since it
is a page about a shop that no longer exists. Failures carry a machine-readable `code` the app
localizes — the backend's messages are English and this app is ru/uz. Shared form widgets live in
`presentation/widgets/store_form_fields.dart`; don't re-privatise or copy them.

---

## 8. Products (`features/products/`)

**One grid, three audiences.** `ProductGrid` + `ProductTile` render the two-per-row layout for the
owner (`ShopProductsScreen`), the customer (the shop card) and the category browse — deliberately the
same widget, because the point is that an owner sees their shop laid out exactly as a customer will.
`ProductTile.height` is a fixed `mainAxisExtent`. An optional `subtitle` carries the shop's name on the
cross-shop browse and caps the product name to one line so the tile keeps its height.

Two rules the tile encodes: an unpriced product shows "Цена не указана" **in brand orange** — the one
place orange is used for something other than a button, because on a fresh shop it is on all 100 tiles
and it *is* the owner's to-do list; and an availability chip appears only for `on_order`/`unavailable`,
since in-stock is normal and a badge on every tile says nothing.

**The customer grid shows only priced products.** An unpriced row is useful to the *owner*, which is
why their own grid shows it, but to a customer it is a tile that answers no question. A shop with
nothing priced gets a line saying so rather than a hidden section, because a missing section reads as
"this app has no products area".

**`ShopProductsScreen`'s `_CatalogueSummary` is the only place in the app that explains the index's
entry condition**, and that is load-bearing: the bar reaching the end is what puts the shop in the
price comparison, and every other surface expresses the rule only by showing nothing. It counts
**template rows only** (`templatePricingProgressFor`) — the owner's own products are not in the shared
basket, so counting them would make the bar finish at the wrong moment in one direction and never
finish in the other. Under the bar: "Осталось N …" while incomplete, "Магазин участвует в сравнении
цен" in green when done. **If the entry rule ever moves, move this line with it.**

`ProductsController` caches **by shop id**, not one list: the shop card is a different shop every time a
pin is tapped, and a single slot would make every reopen a spinner. `forgetShop` is called on delete —
Postgres reuses ids, so a stale entry would eventually serve one shop's products under another's name.
Product counts live on `Shop` (only `/api/shops/mine` computes them), so the edit screen calls
`adjustProductCount(shopId, ±1)` rather than triggering a whole reload for one number.

### The product photo

`ProductPhotoField` on `ProductEditScreen`, backed by `image_picker`. The rules and the endpoint are
root §7; what belongs here is the app's half.

- **Every product in the owner's own shop can take one, template rows included** — including an обои
  slot, which is the case that has no catalogue photo at all.
- **Uploaded the instant it is picked, not on «Сохранить».** The file is on the phone and the row
  already exists, so waiting would leave the owner looking at a picture that is nowhere with nothing
  saying so. It is a separate request with its own busy flag and its own error line on
  `ProductsController` — a photo failing and a save failing are different sentences, and sharing the
  flags would grey out the save button for the length of an upload.
- **A product being *created* has no id to attach a file to**, so the pick waits in the screen's state
  and is uploaded straight after the create returns. If that second request fails the product is still
  saved, and the snackbar says exactly that rather than reporting a failure.
- **The picker is always called with `maxWidth`/`maxHeight`/`imageQuality`.** Those parameters are what
  make the plugin re-encode on the device, which bakes the EXIF rotation into the pixels and turns an
  iPhone HEIC into a jpeg the server can decode (root §8). They also cut a 4 MB camera frame to a few
  hundred KB, which on mobile data is the difference between two seconds and twenty.
- **`PlatformException` from the picker is caught and shown as its own code**, `picker_failed`. It
  never reaches the network — no camera, or access declined — so it has no server code to borrow.
- **The section sits *below* the fields, not above them**, and that is a workflow decision: the job
  this screen is opened for most often is typing one price into one seeded row, a hundred times over
  on a new shop, and a 190px picture at the top puts the price field under the fold every time.
- **"Удалить фото" is hidden, not disabled, when there is nothing of the owner's to remove** — see
  `Product.ownImage`. On a seeded row still showing the catalogue's shot it would put back the picture
  that is already there.
- The local file **wins over the network url** while both exist, and is kept after a successful
  upload: it is the same picture, already decoded on this phone.

### `ProductEditScreen` — one screen, three forms

- **The owner's own product** gets every field.
- **A template product** gets price and availability as inputs and its name, category and unit as
  `ProductLockedField` — plain text with a lock chip, deliberately *not* a disabled `TextField`, since
  a disabled input still looks like it ought to accept typing and the owner finds out by trying. It has
  **no delete button at all**, not a disabled one.
- **An Обои slot** is why the screen reads two flags instead of one: the name field follows
  `product.nameEditable` while category, unit and delete follow `product.isTemplate`. They agree
  everywhere except a slot, where the name is a `TextField` inside an otherwise locked form.
  **Conflating them back into one flag is what would silently re-lock the name.** The hint card
  branches too (`slotProductHint`) — telling an обои owner "название изменить нельзя" over a name field
  they can type in is worse than saying nothing.

`Product.fromJson` defaults `name_editable` to `!is_template`, so an app talking to a pre-slot backend
behaves exactly as before. The rule card explaining the locks sits *above* the fields: read first it
says why three inputs are text; read last it explains a layout the owner has already decided is broken.

**The category field expands in place** (`ProductCategoryPicker`), and it must stay that way. It was
free text (which made the column useless as data), then a Material `DropdownButtonFormField` — which
fixed the data but opens as a menu sized to its longest item, so twelve rows became a slab covering
most of the screen with no visible relationship to the field that opened it. **Do not go back to a
Material dropdown for a list this long.** The bottom sheet `ShopCategorySheet` uses is still right for
*its* job — four rows each carrying two lines of explanation.

> That dropdown left a bug worth recognising by shape: `DropdownButtonFormField` renders the collapsed
> value by **re-using the selected menu row's child**, so a `prefixIcon` plus an icon inside each
> `DropdownMenuItem` painted the glyph twice. Any control with both a leading adornment and a rich
> selected-item widget has this trap.

`ProductCategory.tryFromCode` returns **null** for an unrecognised code (unlike `ShopCategory.fromCode`)
so a pre-000006 free-text row opens the picker empty and forces one deliberate pick rather than being
silently filed under "Смеси". **The price field carries a "сум"/"so'm" suffix, not a currency glyph** —
it showed `CupertinoIcons.money_dollar`, which names the wrong currency for every shop this app has.

---

## 9. Сообщения (`features/messages/`)

**The tab is the support conversation itself, not a list containing one.** Exactly one thread exists
per account, so a list of a single row would be a screen whose only job is to be tapped through. When
chats with shops and masters arrive this becomes that list and the chat moves to a pushed route —
`SupportController` needs no change for it. The wire format and the rules live in root §7.

- **A guest sees why they cannot write rather than a disabled field** — the answer has to arrive
  somewhere, and without an account there is nowhere to put it. `onSignInTap` switches the shell to the
  Profile tab; a standalone route passes null, which hides the button rather than offering one that
  goes nowhere.
- **`isActive` is required, same as the map's.** `IndexedStack` builds every tab and paints one, so
  without that false→true edge a reply sent while the app was open would never appear — the thread was
  fetched at launch and nothing would ask again. `refreshIfStale()` (45s) decides whether the edge
  costs a request, and a *failed* load counts as stale so returning to the tab retries by itself.
- **A live poll keeps the thread current while somebody is actually reading it.** The visibility edge
  alone meant a reply never arrived while the user was *sitting on* the conversation. Root §7 has the
  design and the rejected alternatives; the screen's job is the three inputs — `isActive`,
  `AppLifecycleState.resumed` and the session — reconciled through `_syncWatching` in one
  `addPostFrameCallback` from `build`, because each changes at a different moment and
  `setWatching` is idempotent. **`_support` is captured in `didChangeDependencies`**, since `dispose`
  has to stop the poll and `context.read` during teardown asserts.

#### The keyboard had no way out, and it took four fixes

Once the composer had focus there was no gesture that closed it: the conversation ignored taps, the
list did not dismiss on drag, and back went to a `Navigator` with nothing to pop. The only escape was
force-closing the app. All four are one line each and all four are silent when they break, so
`test/support_chat_test.dart` pins them.

- **Tap** — a `GestureDetector` with `HitTestBehavior.opaque` around the thread. `opaque` is what makes
  it work in the gaps between bubbles; nothing inside the thread is tappable, so it swallows nothing.
- **Drag** — `keyboardDismissBehavior: onDrag` **on the `ListView` itself**. A scrollable claims the
  vertical drag before any ancestor is offered it, so no wrapper could implement this.
- **Back** — a `PopScope` whose `canPop` is false only while this composer holds focus. Inside the
  shell this screen is one child of an `IndexedStack` on the *root* route, so a back press found no
  route and did nothing at all; on most screens the IME swallows BACK first, and here it did not.
  Scoping `canPop` to the focus keeps "back exits the app from the home tab" untouched.
- **Leaving the tab** — `didUpdateWidget` unfocuses on the true→false edge. The `IndexedStack` keeps
  this `State` and its focus alive, so a focused composer kept the keyboard up over the map, the home
  feed and the profile. That was most of what "the keyboard cannot be dismissed" actually was.
- **The first load and every refresh go through `addPostFrameCallback`.** `load()` sets its busy flag
  and notifies before its first `await`, and both `initState` and `didUpdateWidget` run inside the
  build phase (root §8).
- **The user writes on the right in brand orange, support on the left in white.** Side is the primary
  signal and colour the second, because side survives a screenshot and a colourblind reader. The admin
  panel draws the same conversation mirrored — "mine on the right" is a fact about the reader.
- **Nothing is optimistic.** The bubble is appended from the server's response, so it carries the real
  id and timestamp; a bubble that appears and then silently is not there is worse than a second of
  waiting. **A failed send keeps the text in the composer** so nothing is retyped, and the error is an
  inline banner above it rather than a `SnackBar` — the shell's nav bar floats over exactly where a
  SnackBar lands.
- **The list is `reverse: true`** with the item list reversed to match, which opens at the newest
  message and stays there as the keyboard opens, with no `ScrollController` chasing an offset that is
  only known after layout.
- The composer's `maxLength: 2000` mirrors the server's rune limit (Dart counts UTF-16 units, so it is
  a little stricter and never looser) and `buildCounter` returns null to hide the "0/2000" counter.

---

## 10. DevicePreview

**Development-only, and it has been removed and restored twice. Leave it.** It draws the app inside a
phone frame so `make desktop` shows real phone proportions. It was deleted once the `domix` emulator
worked, on the reasoning that a real device beats a picture of one — and that was wrong in a way worth
recording: **the emulator is a real phone running a debug build, and a debug build interprets Dart
rather than running compiled code.** Scrolling stutters there, so it is the wrong place to judge a
layout. The two are not substitutes: the emulator is where the map exists, the desktop is where layout
work is comfortable.

`enabled: !kReleaseMode && !MapConfig.isSupportedPlatform` scopes it to desktop, since on a phone the
device already *is* the frame. `MediaQuery.withNoTextScaling` stays the inner of the two wrappers in
`MaterialApp`'s `builder` slot — **delete the DevicePreview half before release, not that one.**
