# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

---

## 1. Product

**Domix is a marketplace connecting construction shops with customers, built around map-first
discovery.** A customer opens the map, sees the shops near them, and for each one sees what a
standard basket of popular construction materials costs there and whether that is cheaper or dearer
than the market — `4 850 000 сум · на 4% дешевле рынка`.

That single comparison is the product. Everything in the schema and the API exists to make it honest
and comparable. It is also why `shops.location` is a PostGIS `geometry(Point,4326)` with a GIST index
rather than plain lat/lng columns: nearby-shop queries are a primary use case, not a secondary one.

**Next direction:** a job-ticket marketplace. Clients post construction work, workers and teams pick
it up, and workers get a profile with a rating, a photo portfolio and client feedback — layered on the
same user/role system already in `users.role`. The **Заявки** tab is its placeholder.

---

## 2. Working with this repo

The founder is building this while learning Go, Flutter and system design from scratch. It is a real
product headed for production and paying customers, **not** a practice project: hold the code to
production standards while explaining it at a beginner-friendly level.

### How to explain

Every time you touch something non-trivial, cover three things:

- **Syntax** — when you use a Go or Dart feature the founder may not have met (goroutines, channels,
  `sync.Map`, `late`, `Future`/`async`/`await`, mixins, extension methods, pattern matching), explain
  what it does and why it fits here. Don't assume familiarity just because it appears elsewhere in the
  codebase; don't re-explain what has clearly been learned.
- **Data flow** — when a feature spans layers, trace the whole path: button tap → controller →
  repository → HTTP → Go handler → sqlc query → Postgres → response → decode → `ChangeNotifier` →
  rebuild. One layer in isolation teaches less than the journey.
- **Design rationale** — state the *why*, including the alternative you rejected and the reason. If a
  decision was pragmatic (budget, timeline, early-stage constraints) rather than principled, say so
  plainly. Don't dress up a shortcut as architecture.

Plain language, but never at the cost of hiding the real mechanism.

### Confirmed working style

- **When the founder restates something in their own words, check the restatement point by point** —
  quote it, say whether it is right, explain why. A fresh independent explanation that skips
  validating their attempt is much less useful.
- **Always paste the real code inline**, paired with `file_path:line_number` — never a bare line
  number, never a description in place of the snippet.
- **"Word by word" means word by word.** Define every keyword, operator and symbol, even the obvious
  ones, rather than summarising the line's effect.
- **Never explain jargon with more jargon.** Ground every term in what it concretely causes. Prefer
  mechanical precision to analogy, and correct a wrong mental model plainly rather than letting it
  pass.

### Conventions

- **Comments are lowercase**, matching the codebase. They explain non-obvious *why*, never restate the
  code.
- **Build one thing at a time.** Implement what was asked, then stop — no jumping ahead to related
  features or roadmap items.
- **Documentation goes in this file.** Do not edit `docs/docs.md` unless explicitly asked.

---

## 3. Current state

**Recently completed**

- **The Сантехника template is real data now** (2026-08-18) — 58 VERO PPR fittings the founder
  photographed, replacing an invented 50-item list, and the second category to get photos (§8). The
  invented list ran from трубы ППР to газовые колонки and a бойлер; what a fittings shop actually
  stocks is муфты, отводы, тройники, краны and the adapters between them, the same part repeated in
  two pipe diameters (20/25 мм) and two thread genders (В/Р внутренняя, Н/Р наружная) — which is why
  58 rows describe maybe twenty distinct products.
  - **The brand stays in every name** («VERO Муфта 20»), on the founder's call. The cost is real and
    accepted: a template row's name is locked, so a shop stocking another PPR brand prices its own
    муфта under a VERO label. The comparison itself is unaffected — the index groups by
    `template_key`, never by name.
  - **All 58 are `plumbing`, клипсы and хомуты included.** That drops the old list's lone
    `ProductFasteners` row, and it disagrees with universal's нейлоновый хомут, which *is* fasteners.
    The rule used: a tile and a product must denote the same thing, and someone tapping «Крепёж»
    wants дюбели and саморезы, not a saddle clip sized to 20 мм PPR pipe.
  - `PlumbingSize` 50 → 58 **and** `templateSize` in `shop_category.dart` 50 → 58 — the second has no
    test behind it (§4). `templates_test.go`'s photo check is now table-driven over the photographed
    categories rather than universal-only.
  - **Two pairs of photos are byte-identical** (001/002 and 012/013) — the same catalogue shot used
    for two diameters. Each row still owns its own file, so the "no two products share a photo" check
    passes on filenames as intended.
  - **Unseen:** every one of the 58 tiles. A shop seeded with this list has never been drawn — see
    below.

- **A look-and-feel pass on the founder's call** (2026-08-18, later the same day, all of it front-end
  and none of it verified on a phone yet).
  - **Three of the four map glyphs changed** — Универсальный `hammer` → `wrench`, древесные материалы
    `fence` → `tree_pine`, обои `scroll` → `paint_roller` (§8). Two of them reverse a rejection that
    was written down in this file, and all three now share a glyph with a home-screen product tile;
    both are recorded where the set is defined rather than argued again here.
  - **The VIP carousel's off-centre cards recede a little further** — 7% where it was 5% (§8). It was
    briefly 12% plus a 28% fade and that was reverted within the hour: the recede was obvious and the
    neighbours had all but disappeared, which is the wrong trade. **The drop is capped by
    `viewportFraction`** and that is the thing to know before touching it again.
  - **Популярные категории lost its panel, and the tiles did not gain one** (§8, §10). Giving each
    tile a white card of its own was the first attempt and it was rejected on sight — two nested
    boxes per tile reads as clutter. The grey glyph box on the page background is what shipped, so
    the change is a deletion. This still deletes the single exception §10 used to make to "no section
    containers on the home feed".
  - **The categories pager's inactive dot was invisible**, so a two-page grid looked like a one-page
    grid with a stray orange mark under it (§8). `hairline` on `background` is a contrast ratio of
    about 1.02; it is `textFaint` now. Nothing else on that section says a second page exists.

- **The five things the first hour on a phone turned up** (2026-08-18, after the map drew). All of
  these are UX and cache correctness rather than anything the backend does; none of them is reachable
  from a test that does not open a screen.
  - **The home search bar became a button that opens `ProductSearchScreen`.** As a live `TextField`
    in the middle of the feed it raised a keyboard nothing could dismiss — no route to pop, no
    unfocus-on-tap anywhere on that screen, and the feed just scrolled underneath it (§8, §9). The
    new screen is where as-you-type results will go; today it shows the prompt state.
  - **A failed shop load became permanent, and survived restarting the app** (§9). Fixed with the
    tab-visibility edge plus a stale check, and a «Повторить» on the banner.
  - **Deleting an account left its shops on the map.** The public list is a snapshot with no push
    channel, so nothing told it. `AuthController.onSessionEnded` → `StoresController
    .handleSessionEnded(accountDeleted)` now drops exactly the deleted owner's pins and marks the
    snapshot stale; a plain logout drops the *management* list only, since signing out does not close
    anybody's shop. `test/stores_snapshot_test.dart` pins both directions.
  - **A failed deletion showed the Telegram login instructions** (§9). The dialog ignored the message
    it was handed. It now reports the real thing, with a timeout distinguished from a failure —
    pressing «Удалить» again is safe, since `DELETE /api/me` succeeds for an account already gone.
  - **Icons.** Древесные материалы `axe` → `fence` and Универсальный `store` → `hammer` — **both
    superseded the same day**, see the entry above; the location picker's pin is a plain капля instead
    of a building; and the teardrop's tip now meets the circle at its tangent points instead of
    floating below it.

- **First run on real hardware, and the four bugs only real hardware could show** (2026-08-18). Until
  this day the app had never been run on a phone, never been built for release, and nobody had seen
  MapKit draw a frame. All four failures below were invisible to `flutter analyze`, to 35 passing
  tests, and to every debug run on a desktop.
  - **The map drew nothing, for two unrelated reasons that look identical.** The `domix` AVD had
    `hw.gpu.enabled=no` and MapKit is a native OpenGL renderer (§4); and **`mapkit.onStart()` was
    never called**, so its network layer never started (§11). Both present as a grey grid with no
    error anywhere. The Yandex dashboard reading **0 requests** is what proved it was not the API
    key — a rejected key still counts as a request.
  - **Login failed on the phone with "Что-то пошло не так" while Telegram sat on the home screen.**
    Android 11 package visibility: `canLaunchUrl` returns false for every https URL unless the
    manifest declares a `<queries>` intent for it (§9). **The diagnosis came off the server** — ngrok
    showed `POST /api/auth/init` and *zero* `/api/auth/status`, which put the throw between two known
    lines of code.
  - **`proguard-rules.pro` did not exist and R8 had never run.** Written (§4). Flutter's Gradle plugin
    picks it up by filename with nothing to wire up.
  - `make apk-test` and `make dev-skia` were added, and `scripts/ngrok-sync.sh` written, because each
    of those was a manual step whose failure mode was silent.

- **The ⭐ 0.0 rating is hidden rather than printed.** `shops.rating` is still a column nothing
  writes; the app now asks `hasRating` at all three draw sites instead of showing every shop a zero
  out of five (§11).

- **Account deletion, product search and a real launcher icon** — the three code-level things that
  stood between the app and handing it to shop owners (§8, §11).
  - `DELETE /api/me` destroys the account and, through the schema's cascades, its shops and their
    products in one statement. **This is a Google Play requirement, not a feature** — an app that
    creates accounts and cannot delete them is rejected at review. The confirmation lives on the
    screen, not in the API.
  - `GET /api/products/search?q=` backs the home screen's search field, which had been a real
    `TextField` with an empty `onSubmitted` since there was nothing to submit to. The dead filter
    button beside it was **deleted**, not disabled.
  - The launcher icon was still the `flutter create` Flutter logo, with no adaptive icon at all.

- **Pre-release hardening pass.** `POST /api/auth/init` accepted `{"role":"admin"}` and passed it
  straight to `CreateUser`, so anyone could register themselves an administrator — fixed, and the
  admin endpoint is gone entirely (§7). Session ids went from 4 random bytes to 32. Rate limiting
  added (`internal/ratelimit`). `RequireAuth` now checks the user still exists, so deleting an account
  cuts its app off at once instead of in four months. Phone numbers are masked in logs. Android's
  package id, app name and signing config were still `flutter create` placeholders (§11).

- **Only a complete basket earns an index** (migration 000013, §6). One unpriced template row and the
  shop publishes no price, no badge and no contribution to its market — it is a pin on the map and
  nothing more. This replaced the 30% floor *and* the imputation that made the floor workable.
- **The map pin carries the comparison, not the сум.** Per-category glyph inside the pin, coloured
  dot + `−4%` above it, basket price moved into the shop's sheet (§8, Map).
- **The map draws no pins until zoom 13.** Opens at 12 with a "Приблизьте карту" line; one pinch
  brings them in (§8, Map).
- **The Универсальный template is real data now** — 100 products the founder photographed, specified in
  `/products.md`, replacing an invented 50-item list (§8).
- **Products have photos.** `/photos/<категория>/NNN.jpg`, served at `/static/products/`, one per
  template row (§8). `shops.image_url` is still unwritten — this is products only.
- **Обои became a template of ten slots** rather than ten products, which is what keeps wallpaper shops
  inside the Basket Price Index at all (§8).
- Дерево is displayed as **Древесные материалы**. The stored code is still `wood`.
- The home screen reads the database. `GET /api/home` returns the VIP carousel and the tabbed
  "Лучшие предложения"; a category tile fetches its products on tap.
- **Basket Price Index** (§6) replaced the dead `shops.average_paycheck` column. The raw index never
  reaches the app — the server sends a badge.
- **VIP** is a `vip_until` timestamp with an admin-only endpoint, not a boolean somebody has to
  remember to switch off.
- Security and stability pass on the Telegram bot: contact-ownership verification, nil-`From` guards,
  `recover()` in the update loop, `errors.Is(pgx.ErrNoRows)`.
- Request bodies capped at 64 KiB, coordinates range-checked, shop field lengths validated.
- JWT lifetime cut from a year to four months.

**Also unseen from the deletion/search/icon pass:** the launcher icon on a real homescreen. The debug
APK builds and packages all five icon densities plus the adaptive XML — that is verified, and it is
not the same as looking at it.

**Unseen from the 2026-08-18 UX pass**, and every one of these is a screen rather than a rule, so a
test cannot stand in for looking: `ProductSearchScreen` opening from the feed with the keyboard
already up, the prompt state and the "минимум два символа" line under it, results replacing the
prompt in place, and back dropping the keyboard on the way out. On the map: the retry on the error
banner, and switching away and back after a failure clearing it. The капля on the location picker was
rendered off-screen at 6× and looks right; on a phone over map tiles is a different question.

**Unseen from the look-and-feel pass**, and all of it is motion or pixels, so only a phone answers it:
the four glyphs on real pins — **`tree_pine` at 20px is the one to check first**, since a conifer is a
lot of small strokes and it is the newest of the set; the carousel's recede at the speed a thumb
actually swipes; and the categories section with no panel, where the thing to look at is the label —
«Пиломатериалы» still does not fit a tile's width and breaks mid-word, exactly as it did inside the
panel. The whole feed was rendered off-screen at 360dp with a real Cyrillic font loaded (§11 says why
that qualifier matters) and nothing overflows, but a golden is not a screen.

**Not yet run in the real app.** Everything is unit-tested and every endpoint has been curled, but
nobody has watched Flutter draw it: the home screen against a live backend, the price badge, the
"Лучшие предложения" tab strip, the category product grid, creating a shop through the form and seeing
100 seeded tiles, and `POST /api/shops` after the role-lookup change. **Also unseen: an Обои shop's ten
slots, and typing a name into one** — a 100-tile grid and a 10-slot one are both new shapes on that
screen. **And unseen from the 000013 change:** the four category glyphs on real pins, the coloured dot
above them, the sheet's basket-price block, and the progress card's "осталось N" line.

**And unseen from the Сантехника list**: all 58 tiles. The photos serve correctly
(`/static/products/plumbing/001.jpg`, 200, `immutable`) and the names are checked against the
photographs one by one, but no shop has been seeded from this list yet — the one local сантехника
shop (id 29) still carries the old 50 rows and 0 prices, because **seeding happens once, at
creation**. Seeing the new catalogue means creating a *new* shop. Two traps in doing that, in the
order they bite: **restart `go run ./cmd/api` first** — a running process holds the template it was
compiled with, so a stale binary silently seeds the old 50 and reads as "the change didn't work"
(§9, the same shape as the schema/binary mismatch); and the grid is 58 `ProductTile`s, which is the
`shrinkWrap` trap's territory — `ShopProductsScreen` is a `CustomScrollView` and safe, but the map's
shop sheet is not (§9), though it shows only *priced* products so it stays harmless until somebody
prices them.

**The Yandex MapKit map draws.** Confirmed on the `domix` emulator, 2026-08-18 — the first time
anybody has seen MapKit render a frame in this app. It took two fixes that had nothing to do with each
other and both of which looked like a bad API key: the AVD was configured `hw.gpu.enabled=no` (§4), and
`mapkit.onStart()` was never called, so the network layer never started (§11). **If the map is ever
blank again, those two are the first suspects, in that order**, and the Yandex dashboard's request
counter is what separates them from a genuinely bad key.

What that leaves still unseen — everything downstream of a drawn map, roughly in the order it would
fail: whether
`ViewProvider` rasterizes `ShopMarker` at all (it builds off-screen with no `Theme` above it), whether
the teardrop's **tip** lands on the shop rather than its centre (`IconStyle.anchor` 0.5/1.0), whether
a tap on a pin opens the sheet (`addTapListener`, since the widget's own `GestureDetector` is dead),
whether the camera listener survives a garbage collection (§11 — the weak-reference trap; symptom is
a map that ignores the zoom threshold after ten seconds), and whether the location picker's
`onCenterChanged` fires often enough to keep the address in step. An emulator named `domix` is set up
for exactly this.

The one local shop has 0 of 100 priced, so **every price-dependent surface will be empty until somebody
finishes a catalogue** — the map pins will carry no labels, the sheet will show its "ещё не указал все
цены" line, and the home screen will fall back to the showcase. That is the rule working, not a bug;
price all 100 on one shop to see the other half.

**Backend study progress** (file by file, deep): `db/db.go`, `db/queries/shops.sql` +
`db/shops.sql.go`, `internal/dbctx/dbctx.go` and `context.Context` generally,
`internal/auth/middleware.go`, `internal/auth/session.go`, `internal/endpoints/` (cors, auth, shops),
and `cmd/api/main.go` section 5 (route wiring). **Not yet studied:** `internal/telegram/handler.go`,
the remaining `cmd/api/main.go` sections.

---

## 4. Commands

### Backend — run from `backend/`

```bash
go run ./cmd/api      # API server + Telegram bot (loads ../.env)
go build ./...
go vet ./...
go test ./...
sqlc generate         # regenerate db/*.sql.go after editing queries or migrations
```

**Changing what a new shop is stocked with** starts at `/products.md`, not in Go. Add the photo to
`photos/<категория>/` under the next free number, add the row to the right table in the doc, then carry
it into `internal/catalog/templates.go` (inventing a stable `template_key`), bump the `*Size` constant,
and bump `templateSize` in `frontend/lib/features/stores/data/shop_category.dart` — that last one has no
test behind it. `go test ./internal/catalog/` catches a wrong count, a duplicate key, an over-wide value
or a missing photo. Existing shops keep their old catalogue: seeding happens once, at creation.

Migrations use the `golang-migrate` CLI — they are **not** auto-run on startup:

```bash
migrate -database "$DB_URL" -path db/migrations up
```

> If that fails with `SSL is not enabled on the server`, append `?sslmode=disable`. The `migrate` CLI
> requires TLS where libpq (and so `psql` and the app's own pgx pool) defaults to `prefer`, so the same
> `DB_URL` works everywhere else and only trips here.

**After `migrate up` or `sqlc generate`, restart the server.** A running process holds the SQL it was
compiled with and does not notice the schema moving underneath it. This has cost real debugging time —
see §9.

Local Postgres needs the PostGIS extension. Optional pool tuning: `DB_MAX_CONNS` (default 10),
`DB_MIN_CONNS` (default 2).

Required `.env` at the repo root: `DB_URL`, `TELEGRAM_BOT_TOKEN`, `WEBHOOK_URL`, `PORT`, `JWT_SECRET`.

Optional: `TELEGRAM_DEBUG=true` logs every bot update in full (**off by default — the firehose
contains phone numbers**), `TRUST_PROXY=true` makes the rate limiter read `X-Forwarded-For`, which is
**only correct once something in front always rewrites that header** — set it wrong in either
direction and the limiter either buckets the whole internet together or hands attackers a fresh
identity per request. Both failures are silent.

Local loop: `TRUNCATE TABLE users RESTART IDENTITY CASCADE;` to reset users, `ngrok http 8080` to
expose the webhook.

**The tunnel hostname is a reserved static domain now, so it does not move** —
`jeep-prepay-penholder.ngrok-free.dev`, one free per ngrok account. Both env files already hold it:
`.env`'s `WEBHOOK_URL` is where Telegram **pushes** updates in, `env.json`'s `API_BASE_URL` is where
the app **pulls** from. Neither can be localhost — Telegram's servers are on the internet and a real
phone is on mobile data.

**A reserved domain is only used if it is asked for**, and that is the whole remaining risk:

```bash
ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080   # the static domain
ngrok http 8080                                              # a fresh random hostname, silently
```

A random hostname breaks the two files in different directions and neither says "your tunnel moved":
a stale `WEBHOOK_URL` means `/start` never arrives and login hangs on the polling screen; a stale
`API_BASE_URL` means every request times out and the home screen shows the showcase fallback as
though the database were empty (§8).

**`./scripts/ngrok-sync.sh` is the repair for exactly that, and nothing else.** It reads ngrok's own
local API at `localhost:4040` and rewrites both files to whatever is actually running, so it can't be
mistyped — it was written when the free tier handed out a new hostname on every restart, and on the
static domain it is a no-op that rewrites the same two lines. Keep it: it is one command against the
one failure mode left, and a machine with no reserved domain of its own still needs it every restart. **Both files are
read at startup, not live** — after any change restart the Go process (it registers the webhook on
boot) and restart `make dev` (env.json is compiled in; hot reload cannot pick it up).

### Frontend — run from `frontend/`

```bash
make setup      # cp env.example.json env.json, then flutter pub get
make emulator   # boot the domix AVD, leave it running
make dev        # run on Android (-d android)
make dev-skia   # same on the old renderer - a diagnostic for emulator stutter, not a workflow
make desktop    # run on Linux instead - faster, but has no map
make check      # flutter analyze && flutter test
make apk-test   # RELEASE build against env.json - what to sideload before a domain exists
make release    # guard-jdk + guard-prod + check, then the .aab against env.prod.json
```

**`dev` is pinned to the Android device and `desktop` is a separate target on purpose.** Left to itself
`flutter run` takes whichever single device it can see, which on this machine is the Linux desktop -
and MapKit does not exist there, so it would silently run the one build that cannot show the map.
Both targets are supported; the desktop one is genuinely faster for the home screen and the forms.

> `flutter run -d <x>` matches a device's **id or name, never its target platform**, so the literal
> `-d android` the target used to carry matched nothing even with the emulator up — and the error
> printed `android-x64` in the platform column, which reads like the very thing that was asked for.
> `dev` now resolves the id (`emulator-5554`) out of `flutter devices --machine` with `jq`, rather
> than hardcoding it, since a second emulator would be `emulator-5556`. No device → a message saying
> to run `make emulator`.

`make guard-jdk` runs ahead of `dev`, `apk` and `release`, because a JDK-17 build fails several
hundred lines into a Gradle log with `class file has wrong version 65.0, should be 61.0` and names
neither Java nor the JDK.

**Any screen with a map needs a device or an emulator** — Yandex MapKit is Android/iOS only, so a
desktop `flutter run` shows `MapUnavailablePanel` where the map should be (§11). The rest of the app
still runs there, which is the point of the guard. A `domix` AVD (Android 35, Google APIs, Pixel 7,
x86_64) is set up: `flutter emulators --launch domix`.

**The AVD shipped with `hw.gpu.enabled=no`, and MapKit cannot draw without a GPU.** It is a native
OpenGL renderer, so with GPU emulation off there is nothing for it to render onto — and the failure
presents as a blank map rather than as an error, which is indistinguishable on sight from a bad API
key. `~/.android/avd/domix.avd/config.ini` now carries `hw.gpu.enabled=yes`, `hw.gpu.mode=host`
(the host has an NVIDIA GTX 1650), `hw.ramSize=4096` and `vm.heapSize=512`. **`config.ini` is read at
launch, so a change needs a cold boot**: `flutter emulators --launch domix --cold-boot`. A working
GPU announces itself in logcat as `yandex.maps: Chosen EGL config={r=8, g=8, b=8, ...}`.

The AVD has **no Play Store** (`PlayStore.enabled=no`, a Google APIs image), so Telegram cannot be
installed from the store — which matters because login goes through it. Sideload it once; it persists
across restarts, and only a wipe undoes it:

```bash
curl -L -o /tmp/telegram.apk https://telegram.org/dl/android/apk && adb install /tmp/telegram.apk
```

There is also **no device skin installed**, so the emulator window is a bare rectangle rather than a
picture of a phone. Skins ship with Android Studio, not the command-line SDK. It is cosmetic — but it
is why `DevicePreview` was restored (§10) rather than left deleted: the emulator is a real device
running a *debug* build, so it stutters, and it is the wrong surface for judging a layout.

> If `flutter emulators` reports none while `~/.config/.android/avd` has some, the AVDs are outside
> the path Flutter looks in. `ln -s ~/.config/.android/avd ~/.android/avd` fixes it for every tool at
> once.

**Gradle's heap is capped in `android/gradle.properties`, and the number is sized to the machine.**
It is **4 GB** now — the laptop has 16 GB. It was 2 GB, and that was not a tuning nicety: the
Flutter template ships `-Xmx8G -XX:MaxMetaspaceSize=4G` and the machine then had 7.4 GB of RAM in
total, so the default let one build ask for more memory than the computer has — and the JVM does
ask, since it grows its heap until it hits the ceiling rather than until it is done. The symptom was
the whole desktop freezing mid-build and the OOM killer taking whatever it reached first. The file
also caps the *Kotlin* daemon (a second JVM the first setting does not govern) and
`org.gradle.workers.max` (2 GB and 4 alongside the heap's 4). **If a `--release` build ever dies
with OutOfMemoryError, close the emulator before raising anything further** — R8 is the hungriest
step and it only runs for release, and the `domix` AVD now holds 4 GB of its own.
`make gradle-stop` reclaims the daemon's heap when switching to something else.

**Building for Android needs JDK 21 or newer**, because MapKit's plugin ships Java 21 bytecode:

```bash
sudo pacman -S jdk21-openjdk
flutter config --jdk-dir /usr/lib/jvm/java-21-openjdk
```

**Set `--jdk-dir` only after the JDK is actually installed.** Pointing it at a path that does not
exist takes the whole Android toolchain down — `flutter doctor` reports `Cannot execute
/usr/lib/jvm/java-21-openjdk/bin/java`, and every build fails with a bare `Error: Build process
failed` that says nothing about Java. `flutter config --jdk-dir=` (empty) undoes it.

`make guard-jdk` (`frontend/tool/check-jdk.sh`) checks this before every Android build, and it
**resolves the JDK the way Flutter does, not the way the shell does** — the two genuinely disagree
here, because `archlinux-java` still has `java` on PATH as 17 while `--jdk-dir` points at 21. A
naive `java -version` check reports 17 and blocks a build that works. Order: `--jdk-dir`, then
`JAVA_HOME`, then PATH.

**`apk-test` is a release build against `env.json`, and it exists because `apk` cannot run yet.**
`guard-prod` refuses while `env.prod.json` says `REPLACE_ME`, which is correct — but it also blocks
the thing most worth learning early, and that thing has nothing to do with the domain. A release
build is a *different program*: Dart compiled ahead of time rather than interpreted, and R8 deleting
and renaming whatever it believes nothing calls. A wrong `proguard-rules.pro` surfaces as a blank
map in release and in no other build. `apk-test` finds that today; `apk` still has to be run once
the domain exists, because the production address is exactly what `apk-test` does not cover.

The raw commands still work; the Makefile exists so the `--dart-define-from-file` flag is not typed by
hand and so `dev` and `release` cannot be pointed at each other's env file by accident (§11).

`env.json` supplies `API_BASE_URL`, read via `String.fromEnvironment`. It is **gitignored and
per-developer** (it points at that machine's ngrok tunnel); `env.example.json` is the committed
template, so after cloning: `cp env.example.json env.json`.

> `--dart-define` values are compiled into the binary as plain constants and are **recoverable from a
> shipped APK**. Never put a secret in them — those belong behind an authenticated endpoint.

`test/fixtures/api_home_response.json` is **captured from a running backend**, not hand-written:

```bash
curl -s localhost:8080/api/home > test/fixtures/api_home_response.json
```

A hand-typed fixture tests what its author believed the backend sends, and that belief is the thing
most likely to be wrong. The Go side has its own tests for the shape; this one checks the two agree.

### Test suites

Four Go packages under test. `internal/catalog` and `internal/pricing` are pure. `db` and
`internal/endpoints` need a **real local Postgres**: they open a transaction, work, and roll back, so
they never commit and never touch existing data. They read `DB_URL` from the environment (falling back
to the repo-root `.env`) and `t.Skip` cleanly when there is no database, so `go test ./...` stays
runnable anywhere. They run against real Postgres on purpose — what they check is what the *database*
computes, and a mock would only check what the test author believed it computes.

---

## 5. Architecture

### Auth: Telegram-linked login, no passwords

The core non-obvious piece. It spans both halves of the app and is stateful in RAM, not the DB, until
login completes.

1. Flutter POSTs `name` + `role` to `/api/auth/init`. `SessionManager`
   (`internal/auth/session.go`) creates an in-memory session `sess_<base64url>` with status `pending`
   in a `sync.Map`. **No DB row exists yet.** The id is 48 characters and **must stay under 64** —
   Telegram silently drops a longer `start=` payload and the whole handshake dies without an error
   (§9).

   > This flow is unusual in that **the app's own error messages are the least reliable evidence
   > about it.** It spans a phone, a Go process, Telegram's servers and a tunnel, and most of the
   > failures found so far surfaced as a generic "something went wrong" on the phone. The ngrok
   > request log is the real instrument: which of `/api/auth/init`, `/webhook` and
   > `/api/auth/status` arrived, and in what order, localises a break to one step every time.
   > *No status polls at all* means the app threw before step 5. *Polls but no webhook* means
   > Telegram never delivered, which is step 3 or 4 — and a payload over 64 characters looks exactly
   > like that.
2. The backend returns `https://t.me/<bot>?start=<sessionID>` — Telegram's documented deep-link
   format, not the unofficial `tg://` scheme, so it opens the app via verified Universal/App Links and
   degrades to a web preview if Telegram isn't installed.
3. The user's `/start <sessionID>` hits the webhook; `LinkChat` maps `chatID → sessionID` in a second
   `sync.Map`. The bot then asks for a phone number via the contact button.
4. On receiving the contact, the backend reads `name`/`role` for that chat, looks the user up by
   phone, and either logs them in (upgrading `customer` → `shop_owner` if they registered a shop) or
   creates them. `CompleteSession` generates a JWT and marks the session `success`.
5. Flutter polls `/api/auth/status` every ~2s (capped at 60 attempts), then persists the JWT, role,
   name and phone to `flutter_secure_storage`.
6. A sweeper goroutine evicts sessions older than 10 minutes, and on the same pass deletes any
   `chatToSession` entry whose session no longer exists — otherwise a chat that never sends a phone
   number leaks an entry permanently.

**Known gaps:** no refresh token and no revocation list, so the four-month expiry is the only way a
session ever ends. Users can repeat the `/start` + share flow multiple times.

### Backend layout

- **`cmd/api/main.go`** — the single entrypoint, and *orchestration only*: load config, build the pool,
  init the bot, wire dependencies into endpoints, register routes. No handler logic. `cmd/` exists so a
  second binary (a ticket-marketplace worker, say) can be added as `cmd/<name>/main.go` sharing the
  same `internal/` packages.

- **`internal/endpoints/`** — the Flutter-facing API, one file per resource. Handlers are methods on
  small structs whose fields *are* their dependencies (`&endpoints.Shops{Queries: q, JWTSecret: s}`) —
  idiomatic Go DI without a framework. New endpoints follow that pattern.

  | file | holds |
  | --- | --- |
  | `cors.go` | `WithCORS(methods, handler)` — headers + OPTIONS preflight, applied once at registration |
  | `auth.go` | `Auth.Init` / `Auth.Status` — the login handshake |
  | `shops.go` | `Shops` — `Route`/`List`/`ListMine`/`Create`/`Update`/`Delete` |
  | `shop_dto.go` | `ShopResponse` and one mapper per sqlc row shape |
  | `home.go` | `Home.Get` (`/api/home`), `Home.ProductsByCategory` and `Home.SearchProducts` |
  | `product_crud.go` | the four product endpoints |
  | *(no admin.go)* | granting a VIP placement is SQL, not an endpoint — see §7 |
  | `auth.go` | also `Auth.Me` (`GET /api/me`) — "is this session still real, and who am I now" — and `Auth.DeleteMe` (`DELETE /api/me`), dispatched by `Auth.RouteMe` |
  | `authz.go` | `authorizeShopAccess`, `writeAPIError`, the `accessError` type |
  | `request.go` | `decodeJSONBody`, `validateCoordinates` |

  `shop_dto.go` exists because sqlc emits one row struct per query by design — there are six
  near-identical ones — and they are full of `pgtype` wrappers that serialize as
  `{"String":"","Valid":false}` rather than as the null the app expects. The mappers are longhand
  rather than unified behind generics or reflection: Go generics cannot read a field off a type
  parameter, and reflection would trade a compile-time guarantee for a runtime one in the layer whose
  whole job is to be the stable contract with the app.

  `decodeJSONBody` caps the body at 64 KiB and writes its own 400. `validateCoordinates` rejects
  out-of-range values **and exactly `(0, 0)`** — PostGIS happily stores `ST_MakePoint(999, 999)` as a
  valid geometry that is simply nowhere, so an unvalidated shop is written successfully and then never
  appears on the map with nothing in any log to say why. `(0,0)` is a real point in the Gulf of Guinea
  and what it actually means is a form that submitted before a location was picked.

- **`internal/auth/`** — `session.go` (the handshake state machine), `jwt.go` (HS256, four months),
  `middleware.go` (`RequireAuth`).
- **`internal/catalog/`** — the product templates a new shop is seeded from, and the twelve shared
  product-category codes.
- **`internal/pricing/`** — turns the Basket Price Index into a badge (§6).
- **`internal/dbctx/`** — `WithTimeout(ctx)`, a 5s deadline on every DB call. Without it a hung query
  holds a pool connection forever instead of failing bounded, which at a small `MaxConns` starves every
  other request.
- **`internal/telegram/handler.go`** — the bot's update loop (§9 for its three load-bearing guards).
- **`db/`** — sqlc-generated, deliberately top-level rather than under `internal/`. `db/queries/*.sql`
  is the source of truth for SQL; `db/models.go` and `db/*.sql.go` are generated — **edit the `.sql`
  and rerun `sqlc generate`**, never the generated files. `db/migrations/` is the schema source of
  truth.

**Authorization is two questions, not one.** `RequireAuth` proves *who* is calling and that the
account still exists — every other logged-in user passes it. A handler needing a role looks it up
**fresh from the database** every time, because `jwt.go` deliberately carries no role claim: a token
lives months and a role can change inside that window. Don't assume `RequireAuth` alone is sufficient,
and don't reach for a `role` claim, since one doesn't exist.

**The app checks its own session, it does not wait to be told.** `AuthController.checkExistingLogin`
hydrates from secure storage *and* reads the JWT's own `exp` claim — the payload is plain base64 JSON,
so an expired token is detectable offline and the first frame is already a guest screen rather than a
profile that flickers away. `verifySession()` then calls `GET /api/me` unawaited on launch and again
on every `AppLifecycleState.resumed`, which is what makes an account deleted while the phone was in a
pocket land on the guest screen by itself. **Only `SessionExpiredException` logs anyone out** — a
timeout or a 500 is not evidence about the token, and signing users out when the server hiccups is a
worse bug than the one being fixed. `/api/me` also returns the current `role`, which is how a
`customer → shop_owner` upgrade reaches an app installed before it.

**`RequireAuth` reads the database, and that is not optional.** It takes an `auth.UserStore` (an
interface it declares itself; `*db.Queries` satisfies it structurally) and calls `GetUserRole` on
every authenticated request. Without it a deleted account keeps full access for the rest of its
token's four months — nothing in a signed JWT changes when the row behind it disappears, and there is
no revocation list. A missing row answers **401 `account_deleted`**, which is the code the app clears
its storage on; a *failed* lookup answers **503**, never 401, because a minute of database trouble
must not sign every user out. Pinned by `TestADeletedUserIsRefusedImmediately`.

**Connection pool** (`mustConnectDB`): explicitly configured rather than left on pgx's defaults, which
tie `MaxConns` to `runtime.NumCPU()` of whatever machine happens to run the process — an accident, not
a capacity decision. `GET /health` pings the pool. `waitForShutdown` listens for SIGINT/SIGTERM and
shuts down in order (in-flight requests finish, then the pool closes), which is also why the Telegram
loop and the HTTP server each run in their own goroutine: `main()` has to stay free to wait on the
signal.

### Frontend layout

Feature-first: `lib/features/<feature>/{data,presentation}`.

- `data/` — repositories and services doing network or storage I/O.
- `presentation/controllers/` — `ChangeNotifier` view-models consumed via `provider`. Built once in
  `main.dart` and handed to `MultiProvider` as singletons. Controllers needing I/O before first paint
  are awaited above `runApp` and passed with `.value`; the rest use `create:` so provider builds them
  lazily. `AuthController` additionally enforces its singleton with a private static-instance
  constructor, since non-widget code references it directly.
- `presentation/screens/` and `presentation/widgets/` — UI.

Bottom navigation: Home / **Заявки** / Map / Messages / Profile. Заявки is the job-ticket placeholder;
it took the Search tab's slot because search now lives on the map and the home header.
`features/search/` was deleted with that change — `git log` has it.

Localization is custom, not gen-l10n: `core/localization/app_localizations.dart` plus
`language_provider.dart`, a `ChangeNotifier` holding the current `AppLanguage`. Locales are `ru` and
`uz`.

`AuthService` implements exponential backoff with jitter (`_executeWithRetry`). Reuse that pattern
rather than adding ad-hoc retry logic elsewhere.

`core/constants/api_config.dart` (`ApiConfig.serverRoot`) derives the plain server root from the same
`API_BASE_URL` that `AuthService` uses. Anything that isn't an auth call builds its URL off that rather
than hardcoding a base.

---

## 6. The Basket Price Index

The one number the whole product rests on. Three steps, per the founder's specification:

1. **Total the shared basket** for each shop — every template product, at that shop's prices.
2. **Average those totals across the market** — the shops of the same *shop category*.
3. **`index = basket ÷ market average × 100`.** So 100 is the market price, 96 is four percent cheaper,
   106 six percent dearer.

Defined once as the `shop_basket_index` view (migration 000008, tightened by 000013) and joined by
every query that needs it. Grouping the market by shop category is what makes the index comparable at
all: an Обои basket is 10 items and a Универсальный basket is 99, so ranking by raw сум sorted shops by
which template seeded them as much as by price. Dividing by each market's own average cancels the unit.

### Two rules inside the view — each is a bug if reversed

- **Template rows only.** The template is the shared basket, identical in every shop of a category,
  which is the only reason two totals can be compared. The owner's own products would be a basket
  nobody else has. What "identical" means is the **`template_key`**, not the name — an Обои slot is
  named differently in every shop and is still the same basket line, because the key says which line
  it is (§8).
- **The basket has to be complete.** `HAVING COUNT(price) = COUNT(*)` — one unpriced template row and
  the shop has no row in the view at all: no basket total, no index, no badge, and **no contribution to
  its category's market average either**. It stays on the map; it is simply not an active shop.

**Migration 000013 replaced a 30% floor plus imputation, and the two went together because they were
one idea:** let a half-finished shop be ranked anyway, on numbers borrowed from its neighbours. It was
defensible — a raw `SUM` over "whatever is priced so far" inverts the ranking outright, so the gaps had
to be filled with *something* — but a shop at the floor was quoting a basket that was 70% other
people's prices under a badge claiming something about itself. The founder's rule is stricter and says
one thing: **price everything or you are not in the comparison.**

What it costs, and it is the real trade: far fewer shops carry a badge, especially at launch. A
Универсальный owner types 100 prices before appearing in Лучшие предложения at all. That pressure is the
point, but two consequences follow and both are already handled — **the home screen will look thin
until owners finish** (the showcase fallback covers the demo case, §8), and **the rule has to be visible
to the owner**, which is `ShopProductsScreen`'s progress card and nowhere else. Do not make the rule
stricter or looser without moving that card in step.

Both `basket_price` and the tier are nullable end to end (`pgtype.Int8` → `*int64` → `int?`) for the
same reason `products.price` is — and since 000013 they are **null together or present together**. The
view has no partial state, so a screen branching on one having checked the other is handling something
the backend cannot send.

### The mean is deliberate

Step 2 is the arithmetic mean and it stays the mean. Averages are sensitive to outliers — one shop
typing an extra zero drags its category's average and makes every honest shop read as cheaper — and
that is an **accepted MVP tradeoff**. Bad data is handled operationally: an admin panel for reviewing
suspicious prices and verifying shops, plus instructing owners to maintain their prices. **Do not
switch to the median.**

### The raw index is never shown to a user

`ShopResponse` carries `basket_price`, `price_tier` and `price_difference_percent`. **There is no
`price_index` field, and adding one back is a regression.** The number is used for ranking (in SQL) and
for choosing the tier (in Go); nothing in the app has a use for it, and "96" is a comparison the reader
has to be taught to perform.

A card shows:

```
⭐ 4.8
4 850 000 сум
🟢 на 4% дешевле рынка
```

**Every threshold lives in `internal/pricing/tier.go` and nowhere else.** That placement is the point,
not the values:

| index | tier | badge |
| --- | --- | --- |
| `< 98` | `cheaper` | 🟢 "на X% дешевле рынка" |
| `98 – 102` | `average` | 🟡 "Средняя цена по рынку" |
| `> 102` | `dearer` | 🔴 "на X% дороже рынка" |

X is `abs(100 − index)`; the index is already rounded by the view, so it is never rounded twice.

The ±2 band is a placeholder and should be expected to be wrong — it is narrow, so with any real spread
almost every shop lands in a coloured bucket. **Making it dynamic is a change to that one file** (the
obvious version: derive the band from the standard deviation of a category's indices, so "market
average" means "indistinguishable from the middle of this market"). Keeping it server-side is what
makes that a deploy instead of an App Store release plus months of builds disagreeing about what
"cheap" means.

There is deliberately **no minimum market size**. An earlier version withheld the badge below three
shops per category; the launch cohort is 50–70 shops, so no category will be thin enough for that to
matter. A consequence worth recognising, and one that 000013 makes *more* likely rather than less,
since it thins every category: the only shop in a category scores exactly 100 and reads as "market
average", which is correct but looks like a bug on sight.

**Flutter side:** `PriceTier` (`features/stores/data/price_tier.dart`) and `PriceTierBadge`
(`core/widgets/price_tier_badge.dart`) — a coloured dot plus the sentence, in five places. A filled
`Container` circle rather than 🟢/🟡/🔴 emoji: emoji are drawn by whichever font the device ships, so
size, alignment and hue vary per platform, and they would be the only non-Lucide glyphs in the app.
**Colour is never the only channel** — the words say "дешевле" or "дороже" either way.

`PriceTierPinLabel` is the map-pin form: the same coloured dot plus a signed `−4%`, because a pin has
room for four characters and forty are on screen at once. **The dot is what the map is for** — reading
forty labels means reading forty numbers, picking out the green ones is a glance. The average tier
prints `≈` and no number at all: its band is 98–102, so an unsigned "1%" beside a yellow dot invites
exactly the question the tier exists to answer.

---

## 7. Schema

`users` (phone is the unique identity key, `telegram_chat_id` unique+nullable, `role` ∈
`customer`/`shop_owner`/`admin`) → `shops` (one owner, `contact_phone`, nullable `image_url`,
`category` ∈ the four catalog codes, nullable `vip_until`, PostGIS `geometry(Point,4326)` with a GIST
index) → `products`. All child relations cascade-delete.

`shops.image_url` exists but nothing writes it — photo upload was deliberately deferred. When it
returns, that is the natural point to switch `POST /api/shops` to multipart, not before; nothing in the
API is multipart now that the spreadsheet upload is gone.

### Invariants

- **`shops.average_paycheck` must never come back.** It existed from migration 000001 as
  `INT NOT NULL DEFAULT 0` with nothing ever writing it, so every real shop advertised `0 сум` for the
  one number the product rests on. It was invisible only because every display site was guarded by
  `> 0`. Dropped in 000007; replaced by the derived index (§6).
- **`shops.vip_until` is a timestamp with exactly one setter.** A shop is VIP while
  `vip_until > now()`. It was a boolean until 000009: turning a placement *off* was something a person
  had to remember, so a shop that stopped paying kept its slot until somebody noticed — and nothing in
  the system knew the placement was meant to end. A date inverts who has to act. `UpdateShop`
  deliberately omits the column so an owner cannot grant themselves the carousel. The wire carries a
  computed `is_vip` boolean; sending the date would invite a client to compare it against the device
  clock, which the user can change.

  **There is no API for granting it, and adding one back needs a conversation.** `admin.go` and
  `PUT /api/admin/shops/{id}/vip` existed and were deleted: any admin endpoint needs an admin role,
  and a role the API can hand out is a role somebody will ask for — which is exactly what happened
  (`/api/auth/init` accepted `{"role":"admin"}` and created the account). The founder is building a
  separate admin panel, so the placement is granted out of band:

  ```sql
  UPDATE shops SET vip_until = '2026-09-03T00:00:00Z' WHERE id = 1;  -- grant
  UPDATE shops SET vip_until = NULL WHERE id = 1;                    -- revoke
  ```

  An absolute date rather than a duration, for the same reason the endpoint used one: "30 days from
  when" is ambiguous when extending a placement.
- **`users.role = 'admin'` can only be set with SQL.** `/api/auth/init` maps anything that is not
  `shop_owner` to `customer`, and the Telegram handler only ever upgrades `customer → shop_owner`.
  The `admin` value stays in the schema's CHECK constraint because the founder's own panel uses it,
  and `authorizeShopAccess` still honours it — but nothing reachable over the network can assign it.
- **`products.price` is nullable and that is load-bearing.** A seeded product has no price until its
  owner types one, and that is a different fact from "free". `pgtype.Int8` → `*int64` → `int?`.
  Anything treating a missing price as 0 breaks the "укажите цену" prompt that *is* the post-creation
  workflow.
- **`products.template_key` is the only thing distinguishing a template row from the owner's own**
  (`NULL` = theirs). A separate `is_template` flag was rejected: a second copy of the same fact that
  could disagree with the first. Unique per `(shop_id, template_key)`, so re-seeding fails loudly
  instead of doubling a catalogue. **The key must stay stable forever** — it is what identifies "the
  same product across every shop", which is what the whole index depends on. It is also what the
  editing rules key off: a template row may only change `price`/`availability` and cannot be deleted;
  an Обои **slot** may additionally change `name` (§8); the owner's own rows are fully theirs and are
  the only ones the 20-product cap counts.
- **`products.category` holds one of twelve locale-neutral codes** (`mixes`, `blocks`, `lumber`,
  `metal`, `fasteners`, `roofing`, `insulation`, `electrical`, `plumbing`, `paints`, `finishing`,
  `tools`) — the same list the home grid renders, so a tile and a product denote the same thing. It was
  free text, which meant "Крепёж" and "крепеж" were two groups and the value stayed Russian when the
  app switched to Uzbek. Unlike `shops.category` there is **no CHECK constraint**: that one is
  structural, this list is content that grows with the home grid, and a CHECK would make every addition
  a migration. `catalog.IsValidProductCategory` guards the two statements that write it.
- **`products.article` and the Excel bulk upload are gone** (000006). The spreadsheet existed so an
  owner wouldn't type a catalogue from nothing, and a shop no longer starts from nothing. If bulk import
  returns it must be *seeded-catalogue-aware* — match rows by `template_key` and price them, not dump
  custom rows alongside.
- **`shops.rating` is the same shape of bug `average_paycheck` was** — a stored column nothing writes,
  so every shop reads 0.0, including on the VIP cards it orders by. It cannot be derived until a
  `reviews` table exists.

### PostGIS

Shop location is read and written with `ST_MakePoint(lng, lat)` / `ST_X` / `ST_Y` directly in SQL
rather than through a Go geometry type. sqlc generates the `ST_MakePoint` args as untyped `interface{}`
(`StMakepoint`/`StMakepoint_2`) — pass plain `float64`s; pgx encodes them fine. **`ST_MakePoint` takes
(longitude, latitude)**, the reverse of the spoken order.

### sqlc traps, all three hit here

1. **Nullability.** `UpdateShop` originally fetched its trailing number with a scalar subquery in
   `RETURNING`; sqlc typed it non-nullable `int64`, which would have failed at scan time the first time
   anyone edited a shop with an incomplete basket — the common case. A data-modifying CTE plus an explicit
   `LEFT JOIN` makes the generator read it correctly.
2. **Type inference through functions.** `COALESCE(vip_until > now(), false)` generated as
   `interface{}`, pushing a runtime type assertion into the DTO layer. An explicit `::boolean` cast
   fixes it.
3. **Window functions.** sqlc **cannot compile a window function filtered from an outer `WHERE`** — it
   does not carry an alias out of a derived table or a CTE (`column "category_rank" does not exist`).
   That is why the best-offers tabs are four queries in a Go loop rather than one
   `ROW_NUMBER() OVER (PARTITION BY …)`.

In the first two cases the type follows from the query's own shape rather than a config override that
could drift. `db/home_queries_test.go` pins them.

---

## 8. Features

### Product catalogue: category templates

**A shop is not created empty.** The add-store form makes the owner pick one of four categories —
Универсальный (100 products), Сантехника (58), Древесные материалы (10), Обои (10 slots) — and
`Shops.Create` copies that category's list into the new shop **in the same transaction as the shop row**
(which is why `Shops` holds a `*pgxpool.Pool`, not just `Queries`: a half-seeded shop would be
unrecoverable, since seeding only happens at creation). Every shop of a category starts with identical
rows differing only in price, which is what makes the index mean anything.

Templates live in **Go** (`internal/catalog/templates.go`), not a table: nothing joins against them at
runtime, so a table would cost a migration per list edit and buy an admin UI that doesn't exist.
`Template()` returns a **copy** — handing back the map's own slice would let one accidental write
corrupt the template for every shop created afterwards in that process. `templates_test.go` asserts
sizes, key uniqueness and column widths, since ~170 hand-maintained lines fail by producing 98 tiles,
not by failing to compile.

**`/products.md` at the repo root is the human-facing source for the lists; `templates.go` is what
ships.** The founder edits the doc — a table per product category, one row per item, carrying the photo
number, the name, the unit and the `template_key` — and the Go file is brought into step by hand. It is
not `go:embed`-ed and parsed at startup for two reasons: the folder sits outside `backend/` and embed
cannot cross `..`, and a parser would turn a typo in a markdown table into a runtime surprise instead
of a compile error.

### Product photos

**`/photos/<shop category>/NNN.jpg`, served by the API, path stored per product row.** The chain is
`catalog.Item.Image` (`"001.jpg"`) → `Item.ImagePath(category)` (`"universal/001.jpg"`) →
`products.image_path` at seeding → `productImageURL()` → `"/static/products/universal/001.jpg"` on the
wire → `Product.fromJson` prepends `ApiConfig.serverRoot`.

- **The DB stores a relative path, never a full URL.** The host differs between the ngrok tunnel,
  staging and production, so a stored absolute URL would be wrong in two of the three.
- **Files are served off disk** by `staticFiles()` in `main.go`, root from `PRODUCT_IMAGES_DIR`
  (default `../photos`). `http.Dir` is what makes it safe — it refuses paths that climb out of the
  root. `Cache-Control: immutable, max-age=1y` is load-bearing, not a nicety: a photo never changes
  under a given number, and without it a 100-tile grid re-downloads ~4 MB on every scroll back.
- **The originals are ~312 KB each (30 MB total) and must not be served raw.** `/photos` holds copies
  resized to 1000px at JPEG quality 85 — 4 MB for all 100. Regenerate with
  `magick <src> -background white -alpha remove -alpha off -resize '1000x1000>' -strip -quality 85 <dst>`.
- **`_BannerPhoto` uses `BoxFit.contain`, not `cover`** — these are catalogue shots of one object on
  white, and cropping to fill a 118px band cuts the head off a hammer. `cacheWidth: 540` is what keeps
  a 100-tile grid inside its memory budget: without it Flutter holds each decoded photo as a full-size
  bitmap, ~4 MB of RAM apiece regardless of the size it is drawn at.
- **The placeholder is painted underneath the photo, not instead of it**, so it doubles as the loading
  and error state and the tile never flashes white mid-scroll.
- `templates_test.go` asserts every item **in a photographed category** has a photo, that no two share
  one, and that the file exists on disk — the exact failure the "drop a photo in, add a row" workflow
  invites. The categories it checks are a list inside the test (`universal`, `plumbing` today), because
  wood has no photos taken and an обои slot names no product to photograph; adding a category to that
  list is the last step of shooting its catalogue.

The Универсальный list is **100 real products the founder photographed**, replacing an invented 50-item
one. Worth knowing what changed with it: the old list had cement, blocks, rebar and roofing; the real
shop sells мелочёвка, so `blocks`, `lumber`, `metal`, `roofing` and `plumbing` now have **zero** rows in
it, and `tools` has 37 of the 100. Anything that assumed a particular product category is present in the
universal template is wrong — `internal/endpoints/home_test.go` used to hardcode "the universal template
has five `blocks` rows" and now counts them off `catalog.Template` with a non-zero guard.

**Test numbers derived from a template's size must be computed, not written down.** The old 30% pricing
floor was pinned as "15 of 50" in three places and every one of them broke when the list grew; it got a
`pricingFloor(templateSize)` helper, and migration 000013 then deleted the floor and the helper with it.
The lesson outlives both — `db/home_queries_test.go` still says `catalog.UniversalSize`, `full - 1` and
`int64(full) * unitPrice` rather than 99, 98 and 9 900 000. The *indices* stay literals on purpose,
because `n` cancels out of `basket ÷ market average` and an index that moved when a product was added
would mean the view was measuring the wrong thing.

**Category is fixed at creation** — `UpdateShop` omits the column, since changing it would leave the
shop stocked from the wrong list.

Known cost of collapsing product categories onto one twelve-code list: a Сантехника shop's 50 rows are
now almost all `plumbing`, where free text had distinguished Трубы / Фитинги / Запорная арматура. The
universal list has the same shape of problem in `tools`, which absorbs discs, drills, hand tools, gloves
and tape alike; a thirteenth `consumables` code was considered and **not** added, because twelve tiles is
what the home grid's two-page pager is built around.

### Обои: a template of slots, not products

**Обои is the one category where a shared list of products is impossible, and the template's shape is
different because of it.** Two wallpaper shops across the road stock almost nothing in common —
different suppliers, different collections, different articles — so a template of ten named rolls would
be ten rolls nine of which the shop does not carry. Every owner would leave them unpriced — which under
the old imputation rule meant an обои basket assembled out of other shops' prices, and under the current
one (§6) means no обои shop is ever in the index at all.

So the Обои template is **ten slots**. A slot fixes the two things that make wallpaper comparable — its
class and its country — and the owner writes in the product. The founder's split, and it is asserted in
`templates_test.go` off the key prefixes: 3 премиум (one each RU/CN/UZ) + 4 стандарт (2 UZ, 2 RU) +
3 эконом (1 UZ, 2 CN).

The index still works, and this is the whole reason the design is slots rather than "обои shops just
have custom products": what gets compared is `wallpaper.premium_ru` here against `wallpaper.premium_ru`
there — premium Russian wallpaper against premium Russian wallpaper. Different rolls, fair question. Had
обои dropped out of the template system, its shops would have dropped out of the index and out of
Лучшие предложения altogether. Ten slots is also the shortest road into the index there is — an обои
owner names and prices ten rows where a Универсальный owner prices 100 (§6).

A slot is a template row **in every respect but one**: seeded at creation, counted in the basket,
undeletable, category and unit locked. Only the name is the owner's.

- `catalog.ownerNamedCategories` (`= []Category{CategoryWallpaper}`) is the single declaration, and
  `IsOwnerNamedSlot(key)` derives the key set from the template itself. **Do not hand-write a list of
  slot keys** — that is a second copy of "which rows are slots" that can disagree with the template
  describing them, the same reason `products.is_template` was rejected.
- `UpdateProductSlot` (SQL) is `UpdateProductPricing` plus `name`. The unit stays out of the `SET` list
  and it matters *more* here, not less: the ten rows are already ten different products in every shop,
  so "за рулон" is the last thing holding the comparison together.
- `ProductResponse` carries **two** booleans now, `is_template` and `name_editable`, because the edit
  form asks two independent questions and a slot answers them differently. They agree on every other
  row. `templateFlags(pgtype.Text)` derives both in one place.
- `Products.Update` is a three-way `switch` — slot / template / own — where it was an `if`.
- **Known limitation, deliberate:** rolls come 0.53 m and 1.06 m wide, and per-roll pricing reads a
  wide-roll shop as expensive. Per m² would be correct and is not how the trade sells. Revisit on real
  data.

Endpoints (`product_crud.go`):

| method | path | who |
| --- | --- | --- |
| GET | `/api/shops/{id}/products` | public — a customer browsing the map has no account |
| POST | `/api/shops/{id}/products` | owner; capped at 20 of their own (`template_key IS NULL`) |
| PUT | `/api/products/{id}` | owner; branches on `template_key` |
| DELETE | `/api/products/{id}` | owner; **refuses template rows** |

The seeded rows are deliberately **outside** the 20-product budget — counting them is what made a
fresh shop show "30 из 20". The cap is checked in Go because "at most 20 rows matching a predicate"
isn't expressible as a CHECK.

`PUT` is the most-used of the four: it fills in the prices a seeded catalogue is missing. A template
row goes through `UpdateProductPricing`, which has no `SET` for name/category/unit **at all** — the
rule is enforced by the statement's shape rather than by trusting the client, since a renamed template
row silently stops being the same product as its counterpart down the road. The app sends those three
fields back unchanged and they are ignored, not rejected. `DELETE` refuses template rows so a shop
can't look cheap by deleting the expensive half of the shared basket.

`authorizeShopAccess(ctx, q, userID, shopID)` is the "is this caller a shop_owner **and** the owner of
*this* shop" check, needed in six places. `nil` means allowed. `Products.authorizeProductAccess` reads
the product first and authorizes against the `shop_id` **on that row**, never one the client sent —
otherwise a caller could pair their own shop's id with someone else's product id.

### Home screen

**`GET /api/home` returns two things: the VIP carousel and the tabbed best offers.** One endpoint
rather than three, because the screen always renders together — one round trip, one spinner, one error
state instead of three that can disagree. It runs five queries sequentially (one VIP, four best-offer
tabs); fanning them into goroutines would take five connections out of a pool of ten to serve one
request, which starves the pool faster than the serial version is slow.

**VIP Магазины** (`VipShopsCarousel`) — shops with a live placement, inner-joined to the index and
ordered by rating, so the tier decides who is *eligible* and quality decides the order within it. VIP
shops are **not** excluded from best offers: VIP is a placement tier, not a separate catalogue, so one
that is genuinely cheap earns a row on merit.

The carousel is a page-snapping loop that never ends in either direction. `PageView.builder` with a
null `itemCount` is unbounded *forwards only*, so it opens at page `5000 × shops.length` and maps the
index with `%` — the origin is an exact multiple of the shop count so it starts on the first shop, and
Dart's `%` is Euclidean (`-1 % 5 == 4`) so the mapping holds below the origin too. Guard the empty
list: `index % 0` throws. `viewportFraction: 0.84` leaves an edge of the neighbours visible.

**An off-centre card recedes 7%, by scale alone, and the number is capped by `viewportFraction`.** A
card scales about its own centre, so every point of shrink slides its inner edge away from the screen
and eats the neighbour's visible sliver: on a 360dp phone that peek is ~16px at a 5% drop and ~6px at
12%. **So "make the effect stronger" and "leave an edge of the neighbours visible" are the same
dial pulled in opposite directions.** 12% plus a 28% fade was tried on 2026-08-18 and reverted the
same day — the recede was unmissable and the neighbours had all but vanished, which loses the thing
the peek is for: saying there are more of these. 7% is the original 5% nudged, which was the actual
ask. Wanting more than that means bringing `viewportFraction` down with it (0.80 buys back roughly
what 12% costs) and accepting a narrower card everywhere.

The card puts the **shop's name on the cover image in brand orange**, top-left, opposite the rating
badge on one line. The name used to head the content block, which put the boldest thing on the card
*under* a large empty image. A dark gradient scrim was tried behind it and **removed** — over a pale
peach placeholder there is nothing to protect text from, so all it did was smear grey across the top
third of every card. When photo upload lands, the fix is the treatment already on this card: a white
pill like the rating badge, which works over any image and keeps both ends of the line symmetrical.
Below the image: address, then the basket price as the largest element, then the badge — separated by
fixed gaps rather than `spaceBetween`, so the rhythm is the same on every card.

**Лучшие предложения** (`BestOffersList`) — cheapest shops, **one segment per shop category**. A comparison
only means something inside a category: a Сантехника basket is a different list of goods from a
Универсальный one, so "на 4% дешевле рынка" refers to a different market on each row. The index makes
the rows *sortable* against each other, but stacking the badges in one column invites comparing 4%
against 6% when the two are measured off different baselines. All groups arrive in one response
(bounded at 4 × 10 shops), so switching is never a network request. **Only categories with ranked shops
become segments**, and with one populated category the control is not drawn at all rather than showing
a single permanently-selected pill, which reads as broken.

The filter is an **iOS-style segmented control**: one recessed `trackGrey` track with a white pill that
slides to the selection over `AppMotion.base`. **Every segment is exactly the same width**, taken from
the container and not the text — "Универсальный" is eleven characters and "Обои" is four, so sizing to
content would make one segment three times another and the options would stop reading as peers; a long
label ellipses instead. Up to four segments divide the width evenly; beyond that they take a fixed
width and the whole track scrolls, keeping the same pill, height and rhythm. There are four shop
categories today, so that branch is unreachable — it exists because a fifth is a plausible product
change and discovering the control collapses *then* is a worse time to find out. The pill sits
*behind* the labels so the transition reads as one object sliding rather than two labels swapping
styles, and no segment paints its own background (one that did would double up mid-transition and
flash). A `TabBar` is the wrong shape here: it brings an underline indicator and its own typography,
and it sizes tabs to their labels.

It replaced "Магазины рядом с вами" and is **not** a proximity list — there is no location input at
all, which is why the rows show no distance.

**Популярные категории** (`PopularCategoriesGrid`) — twelve tiles, the same `ProductCategory` enum the
backend stores in `products.category`. Labels and glyphs hang off that enum via exhaustive `switch`es,
so a thirteenth category is a compile error rather than a blank tile.

- **A two-page pager, not a three-row grid, and no "Все →".** Twelve tiles laid out statically
  dominated the feed; two rows of four is the shape the screen was designed around. The pager *is* the
  control that reveals the rest, so a link promising more would be a second door to the same room.
- **No shop counts.** The tiles briefly carried a badge saying how many shops stocked each category,
  and it cost a database aggregate on every home load to tell a customer something they hadn't asked. A
  tile is a way in, not a statistic.
- **No white surface in this section at all — not behind it, not behind a tile** (2026-08-18, the
  founder's call; it reverses the one exception §10 used to carve out). The grid sat inside a single
  white panel, which grouped the twelve tiles by drawing a box round all of them and made this the
  only section on a container-free feed to have one. Giving each tile its own white card instead was
  the first attempt at removing it and was rejected on sight: a framed card holding a second framed
  box is two borders per tile, twelve times over. What ships is the grey glyph box and its label on
  the page background — one deleted panel, and one token change the deletion forced.
- **The glyph box is `trackGrey`, and it had to change when the panel went.** It was `cardGrey`
  (`#F1F3F6`), which is a light grey chip against a white panel and is *lighter than the page* once
  the panel is gone (`background` is `#EFF1F5`) — so the tiles stopped looking grey and started
  looking white, which is what they were reported as. `trackGrey` (`#E4E7EC`) is the only token in
  the ramp deliberately below the page. **The lesson generalises: a fill is grey relative to what is
  behind it, so moving a surface out from under a widget can silently invert what its fill means.**
  No border with it — `hairline` is lighter than `trackGrey` and would ring a darker fill in a paler
  line.
- **The label is top-aligned under the glyph box, not centred in the cell.** Centring pushes the box
  down by half a line on whichever tiles wrap to two lines, so a row of four ends up with its icons at
  two different heights — and which tiles wrap changes with the display language. `Expanded` round the
  `Text` gives it a tight height, and a paragraph in a tight box paints from the top.
- **The pager's inactive dot has to be visible or the second page does not exist.** It was `hairline`
  (`#ECEEF2`) on `background` (`#EFF1F5`) — a contrast ratio of about 1.02, which drew one orange pill
  and nothing beside it, and the section read as a single page of eight categories. It is `textFaint`
  now. This is the *only* affordance for the second page: a full page of tiles leaves no edge of the
  next one showing, the way the VIP carousel's `viewportFraction` does.
- **Cells are sized with `mainAxisExtent`, not `childAspectRatio`.** Aspect ratio derives height from
  width, so cells grew on wide phones and shrank on narrow ones, and when the section briefly sat
  inside the padded panel the computed height no longer fit a two-line label.
- `_PageDots` rebuilds off the `PageController` as a `Listenable`, not off `onPageChanged` — that
  callback fires once, *after* the page snaps, so the indicator lags the finger. Guard
  `controller.hasClients && controller.page != null`; both are false on the first frame.
- Spacing under the pager is tight on purpose: the dots carry their own touch padding, so matching the
  top inset counts that space twice and pushed Лучшие предложения off the first screen.

**Tapping a tile opens `CategoryProductsScreen`** — every priced product in that category across every
shop, cheapest first, rendered with the same `ProductGrid`/`ProductTile` the owner's catalogue and the
map's shop sheet use. It used to open a list of *shops*, which answered a different question and left
the customer to open each one and search it. Each tile carries its shop's name as a subtitle, because a
price with no seller attached is not actionable.

**The showcase fallback.** `home_showcase_content.dart` holds invented shops shown only while the
database has none, so the app demos — a first screen of three empty states does not. **The substitution
lives in `HomeController._applyContent` and nowhere else** — the widgets take one type and cannot tell
the difference; fallback logic spread across three widgets is three places to forget to delete. The
rule is **all-or-nothing**: showcase rows appear only when a section is completely empty (or the
request failed, the bad-wifi demo case), never topped up into a real list, because two kinds of thing
in one list with nothing distinguishing them is how a demo becomes a bug report. Going to production
is: `kShowcaseFallbackEnabled = false`, check the screen, delete the file. Everything in it is
*derived* from one catalogue — the tabs, the tiers, the drill-down products — so the showcase
demonstrates the real mechanism rather than picturing it, and a tile can never disagree with what
opening it shows.

`home_screen.dart` deliberately puts **no horizontal padding on its scroll view** — each block applies
the shared `_gutter` (16px) itself, which is what keeps headings aligned with the DOMIX pill while
letting `VipShopsCarousel` bleed to the screen edges.

**Search is its own screen, and the bar on the feed is a button that opens it.** Tapping
`SearchAndLikeBar` pushes `ProductSearchScreen` — a field in the app bar, and below it the prompt
state until something is searched. `GET /api/products/search?q=` returns the same shape
`/api/categories/{code}/products` does, so both render through `ProductResultsView`: one widget
owning the loading, error, empty and grid states, wrapped by `ProductResultsScreen` (a title, for a
category tile) or by the search screen (a field). That sharing is the point: browsing and searching
produce the same objects, and a second grid for them is a second set of loading, error and
pull-to-refresh states to get right (and the `RefreshIndicator` trap in §9 to fall into twice).

**The bar became a button because an inline field trapped the keyboard**, and that is a §9-grade
trap rather than a styling preference — see it there. What matters here is that this is *not* a
return to the styled-`Text` version: this control does exactly what it looks like it does when
pressed, which is navigate. A field that raises a keyboard nothing can dismiss is the worse lie.

- **A new query is a new `Key`, not a mutation.** `ProductResultsView` fetches once from its own
  `initState` and holds the result; re-running means `ValueKey(query)` so Flutter builds a fresh
  State. The alternative — swapping the query on the live State — has to race the new request
  against the one still in flight, which is a bug to write rather than a feature.
- **The results stay put while the field is being edited**, and clearing the field goes back to the
  prompt rather than to the last results. An empty field over a list of цемент is the two halves of
  the screen disagreeing about what is on it.
- **As-you-type is deliberately not built yet** — the founder asked for the screen, not the
  behaviour. It is `onChanged` behind a debounce instead of `onSubmitted`, and the reason to wait is
  below: every keystroke past two characters is a sequential scan.

- **`ILIKE '%q%'` is a sequential scan of `products`, knowingly.** A leading wildcard cannot use a
  btree index. It is sub-millisecond at launch scale and it is what makes "мешок" find "Цемент в
  мешках"; a prefix-only search would be indexable and would fail the query people actually type. The
  fix when the table grows is a `pg_trgm` GIN index on `lower(name)` — a migration, not a rewrite.
- **`%` and `_` are escaped before they reach the pattern** (`escapeLikePattern`). Not a SQL-injection
  concern — the query is a bound parameter — but to LIKE they are instructions, so an unescaped
  search for "50%" returns the entire catalogue. That looks like a broken search rather than a
  security bug, which is exactly why it would survive review.
- **The floor is two characters, counted in runes.** `len()` counts bytes and every Cyrillic letter is
  two of them, so a byte-length floor of 2 would accept a single letter — which matches a large share
  of the catalogue and costs a full scan to return noise. The app enforces the same floor before
  navigating (`SearchResultsScreen.isSearchable`), so the server's check is the backstop rather than
  the only one.
- **The filter button was deleted, not disabled.** It was a `Container` with `onTap: () {}` — the same
  "picture of a button" the search field itself used to be, and the last one on the screen. There is
  nothing to filter by yet; it comes back when it filters something.

The header's controls are all real (`home_header.dart`), where they were once non-interactive
`Container`s that looked like buttons. The **city pill** opens the same `LocationPickerScreen` the
add-store form uses and keeps only the city; `CityController` ignores a blank city and a
case-insensitive match, so moving the pin within one city rebuilds nothing. The **bell** opens a
permanently-empty notifications screen, because an icon that does nothing reads as broken where an
empty state reads as "nothing yet". Known wart: once picked, the city pill stops following the app
language until it is re-picked.

### Map (`features/map/`)

- **Both maps are rotation-locked.** A two-finger twist would leave every teardrop pin on its side
  with its price label upside down. Under MapKit this is `rotateGesturesEnabled = false` plus
  `tiltGesturesEnabled = false` (a pin drawn flat on a tilted plane is unreadable), set once in
  `DomixMap`. It used to take a `flags` bitmask *and* a separate desktop-only
  `cursorKeyboardRotationOptions` opt-out. Pan/zoom/fling are untouched.
- **The map is deliberately not inside a `SafeArea`** — a map is a canvas and must run edge to
  edge under the notch; only the overlay controls are wrapped. Wrapping the map padded the notch band
  away and left a dead strip. Same reason it sets `AnnotatedRegion<SystemUiOverlayStyle>` dark.
- **Attribution is MapKit's, not ours** — see §11. The hand-rolled OSM pill is deleted.
- Camera moves go through `_flyTo` → `DomixMapController.flyTo`, which is one native call.
  `flutter_map` had no camera animation at all, so this used to be a hand-rolled
  `AnimationController` plus three tweens driven frame by frame; all of that is gone.
- **Pins are withheld below `MapScreen._minShopZoom` (13), and the map opens at 12.** So it opens with
  no pins and a "Приблизьте карту · 47 магазинов" line, and one pinch brings them in — the behaviour
  every map app has. The threshold is deliberately *above* the initial zoom; equal to it, the rule
  would only ever fire on the way out.
  - **Off-screen culling is not ours and must not be reimplemented.** MapKit culls natively. What
    culling cannot help with is the case the threshold exists for: zoomed out over a city, *every*
    shop is inside the viewport, so all of them lay out, rasterize and draw.
  - **The state is a bool, not the camera.** The camera listener fires every frame of a pinch or
    fling; holding the zoom in state would rebuild the pin list at 60fps. `_onZoomChanged`
    compares `zoom >= _minShopZoom` against the stored bool and only calls `setState` when it flips —
    twice per crossing.
  - Search reaches any shop from any zoom: `MapSearchPanel` matches in memory against the full list,
    and picking a result flies to `_focusedZoom` (16), which trips the threshold on its own because
    MapKit reports programmatic moves through the same listener.
  - `test/map_zoom_test.dart` pins it, and pins it against *both* ways of getting it wrong — a
    threshold below the initial zoom (feature never fires) and one above any zoom a user reaches (map
    permanently empty). Both are silent: the screen still renders either way. It drives the camera by
    calling `DomixMap.onZoomChanged` directly rather than synthesizing a pinch, and it asserts on
    **`DomixMap.pins`, not on `ShopMarker` widgets** — pins are rasterized off-screen, so
    `find.byType(ShopMarker)` finds nothing at any zoom and would pass and fail for the wrong
    reasons. The pin list is the last thing on our side of the boundary.
- **A pin says two independent things in two channels.** The teardrop stays brand orange and carries a
  glyph for the *shop category* (`ShopCategory.icon` — wrench / bath / tree_pine / paint_roller), so forty
  identical markers become four readable groups; the label above it carries the *price comparison*
  only, as `PriceTierPinLabel` (§6). Conflating them — colouring the pin by tier — was rejected:
  category is always known and tier usually is not, so the pin would have three price colours plus a
  fourth "no data" colour and the category would have nowhere left to live.
- **Pick map glyphs by rendering them, not by their names.** Lucide's names lie often enough that
  three of the four were wrong on the first pick. `wallpaper` is a *monitor with a picture in it* —
  the desktop-background sense — and shipped looking like a TV; `swatch_book` was accurate (it is the
  sample fan an обои shop hands you) and still failed, because at 20px "fan of swatches" is not a
  thing anyone recognises. **`logs` is a log *file*** — three lines with bullets, the programmer's
  sense — so there is no timber glyph in the family at all, which is what sent древесные материалы
  through `axe` and `fence` first. `droplets` is a weather forecast; `bath` is the one of the four
  that has never moved. To check a candidate without launching the app, render the codepoint out of
  `~/.pub-cache/.../flutter_lucide-*/lib/fonts/lucide.ttf` with ImageMagick — **onto the orange
  circle at 22px**, not as black-on-white at 96, since the question is what survives at pin size.
- **Three of the four are the founder's pick as of 2026-08-18, and each overrode an argument that had
  been written down here.** Универсальный `hammer` → **`wrench`** (and `store` → `hammer` before
  that), древесные материалы `fence` → **`tree_pine`** (via `axe`), обои `scroll` → **`paint_roller`**.
  The thread through all three is *name the material the shop sells, not something adjacent to it* —
  and two of them reverse a rejection recorded above: `tree_pine` was ruled out as a park landmark on
  a map full of them, which is much weaker in place than on paper, since this glyph is white inside
  an orange teardrop and no map tile ever is; `scroll` was accurate about the unit обои are sold in
  (за рулон) and still had to be explained, where a roller is what the trade's own signage uses.
  **Not `hard_hat`** for универсальный — the Заявки tab wears that one, and a glyph must not mean
  "workers" in the nav and "магазин" on the map.
- **Known cost of that set, accepted: three of the four now share a glyph with a home-screen
  `ProductCategory` tile** — `wrench` with Инструменты, `tree_pine` with Пиломатериалы,
  `paint_roller` with Краски. The two lists mean different things (a kind of *shop* against a kind of
  *product*) and never appear on the same surface, so nothing is ambiguous in place; what it costs is
  that a customer who learns the home grid first arrives at the map with those glyphs already meaning
  something narrower than the shop they mark. `ShopCategory.icon` carries the full reasoning, and it
  supersedes every earlier note here pinning a category to `store`, `axe`, `fence` or `scroll`.
- **The basket price in сум is not on the map.** It used to sit above the pin; forty seven-digit
  numbers competed for the same few hundred pixels and none of them was labelled. It moved into the
  shop's sheet (`_BasketPriceBlock`) where there is room to say what the number is, and the pin kept
  the one thing that is scannable at that size — a coloured dot and `−4%`.
- The shop sheet ends with the product grid, deliberately **below** the call button: someone who
  tapped a pin wants the address and phone first. Its head is now name → rating + category → the
  basket-price block; the category line is there as the **legend for the pin's glyph**, and it draws
  the same icon.
- **`MapPinIcon`'s `category` is nullable, and the null case is a plain капля** — the teardrop with a
  white hole punched through it, the mark every map app uses for "this exact point". It drew
  `building_2` until 2026-08-18, and that was wrong twice over: the location picker is not pointing
  at a building but at wherever the user has dragged the map to, which may be a yard or a stretch of
  road, and a glyph there made the picker's pin read as a fifth shop category. A hole claims nothing,
  which is the right amount to claim about a point somebody is still choosing.
- **The teardrop's triangle meets the circle at its tangent points.** It used to put the base at a
  fixed fraction of the width, so the sides crossed the circle at an angle and the join pinched to
  almost nothing — at 48px with no glyph inside, the tip read as a separate little triangle floating
  below a ball. `_PinPainter` now solves for where a line from the tip grazes the circle
  (`x = cx ± r·√(1 − r²/d²)`, `y = cy + r²/d`, from the right angle a radius makes with a tangent)
  and unions the two paths, so the white rim traces one silhouette instead of cutting through the
  join. Shop pins get the same fix; the tip stays at the bottom centre, which is what
  `IconStyle.anchor` 0.5/1.0 assumes.
- `map_search_panel.dart` searches two sources and labels them separately — shops matched
  **synchronously in memory** from the already-loaded list, addresses through Nominatim (debounced
  450ms, 3+ chars, to stay inside its ~1 req/sec policy). Result rows use
  `InkWell(canRequestFocus: false)`; otherwise tapping one pulls focus off the field and hides the
  panel before the tap lands.
- `location_picker_screen.dart` uses "move the map, not the pin" (the pin is a fixed overlay at the
  screen centre, not a map object) and reverse-geocodes the centre 700ms after the map stops.
- `geocoding_service.dart` — free Nominatim, ~1 req/sec. Use `reverseGeocodeDetailed` when a **city**
  is needed: `display_name` cannot be split reliably (a district containing a comma breaks it). OSM has
  no single "city" tag, so `_citySearchOrder` tries `city → town → village → municipality → county →
  state`. `accept-language` means the city arrives already translated.
- Nominatim and the public tile server both want revisiting (self-hosted or paid) before real traffic.

### Shops (`features/stores/`)

`stores_repository.dart` talks to the real backend. On create, the new `Shop` is appended directly to
`StoresController`'s in-memory list so it appears on the map immediately. `StoresController.updateShop`
/`deleteShop` write through to **both** `_myShops` and `_stores`, so the map pin moves or disappears at
the same moment the management row does — and `updateShop` merges the known `productCount` back in via
`copyWith`, because `PUT /api/shops/{id}` doesn't return it.

`data/shop_category.dart` mirrors the backend's four codes. `templateSize` (99/50/10/10) is knowingly
duplicated from `internal/catalog`: it is only shown as a hint *before* the shop exists, so there is
nothing to fetch it from — **so it has to be edited by hand whenever a template's size changes, and
nothing catches it if you forget.** `fromCode` defaults an unknown code to `universal`, right for a single row;
`tryFromCode` returns null for the one caller where guessing would be worse — the best-offer tabs,
where defaulting would merge a fifth category's shops into Универсальный.

The category picker is `StoreCategoryTile` + `ShopCategorySheet`, shaped like `StoreLocationTile`
rather than a Material `DropdownButton`: a dropdown menu has no room for the per-category description
and catalogue size. **There is no edit-form counterpart on purpose** — category is fixed at creation.

**The per-shop management flow is a hub, not one page.** `MyShopsScreen` → `ShopSettingsScreen` →
`ShopProductsScreen` ("Товары") or `EditStoreScreen` ("Данные магазина", including delete). It was one
screen; the split is deliberate, because managing a catalogue and "rename or destroy this shop" are
unrelated, and a destructive action sharing a scroll view with a routine one is how a shop gets deleted
by accident. **A new per-shop feature should become a third section**, not more controls on an existing
screen.

There was a third row, "Загрузка из Excel", and it is **deleted** — screen, repository method,
controller state, localization, `file_picker`, and the backend endpoint. It wrote `template_key IS NULL`
rows, so an upload of 50 put a shop past the 20-own-products cap: the literal cause of "30 из 20".

`EditStoreScreen` pops `true` on delete and `ShopSettingsScreen` pops itself on seeing that, since it is
a page about a shop that no longer exists. Failures carry a machine-readable `code` the app localizes,
matching the product endpoints' contract — the backend's messages are English and this app is ru/uz.

Shared form widgets live in `presentation/widgets/store_form_fields.dart`. Don't re-privatise or copy
them.

### Products (`features/products/`)

**One grid, three audiences.** `ProductGrid` + `ProductTile` render the two-per-row layout for the owner
(`ShopProductsScreen`), the customer (the map sheet) and the category browse — deliberately the same
widget, because the point is that an owner sees their shop laid out exactly as a customer will.
`ProductTile.height` is a fixed `mainAxisExtent` for the same reason the categories grid is. An optional
`subtitle` carries the shop's name on the cross-shop browse and caps the product name to one line so the
tile keeps its height.

Two rules the tile encodes: an unpriced product shows "Цена не указана" **in brand orange** — the one
place orange is used for something other than a button, because on a fresh shop it is on all 100 tiles
and it *is* the owner's to-do list; and an availability chip appears only for `on_order`/`unavailable`,
since in-stock is normal and a badge on every tile says nothing.

**`ShopProductsScreen`'s `_CatalogueSummary` is the only place in the app that explains the index's
entry condition**, and after migration 000013 that is a load-bearing job rather than a nicety: the bar
reaching the end is what puts the shop in the price comparison, and every other surface expresses the
rule only by showing nothing. It counts **template rows only** (`templatePricingProgressFor`), because
the owner's own products are not in the shared basket — counting them would make the bar finish at the
wrong moment in one direction and never finish in the other. Under the bar: "Осталось N …" while
incomplete, "Магазин участвует в сравнении цен" in green when done. **If the entry rule ever moves,
move this line with it.**

**The customer grid shows only priced products.** An unpriced row is a real product the owner hasn't
reached yet — useful to *them*, which is why their own grid shows it — but to a customer it is a tile
that answers no question. A shop with nothing priced gets a line saying so rather than a hidden section,
because a missing section reads as "this app has no products area".

`ProductsController` caches **by shop id**, not one list: the map sheet is a different shop every time a
pin is tapped, and a single slot would make every reopen a spinner. `forgetShop` is called on delete —
Postgres reuses ids, so a stale entry would eventually serve one shop's products under another's name.
Product counts live on `Shop` (only `/api/shops/mine` computes them), so the edit screen calls
`adjustProductCount(shopId, ±1)` rather than triggering a whole reload for one number.

`ProductEditScreen` is one screen for add and edit but **not one form**. The owner's own product gets
every field. A template product gets price and availability as inputs and its name, category and unit as
`ProductLockedField` — plain text with a lock chip, deliberately *not* a disabled `TextField`, since a
disabled input still looks like it ought to accept typing and the owner finds out by trying. It has **no
delete button at all**, not a disabled one. The rule card explaining both sits *above* the fields: read
first it says why three inputs are text; read last it explains a layout the owner has already decided is
broken.

**An Обои slot is the third form, and it is the reason the screen reads two flags instead of one.** The
name field follows `product.nameEditable`; the category, the unit and the delete button follow
`product.isTemplate`. They agree everywhere except a slot, where the name is a `TextField` inside an
otherwise locked form. Conflating them back into one flag is what would silently re-lock the name.
The hint card branches too (`slotProductHint`) — telling an обои owner "название изменить нельзя" over a
name field they can type in is worse than saying nothing. `Product.fromJson` defaults `name_editable` to
`!is_template`, so an app talking to a pre-slot backend behaves exactly as it did before.

**The category field expands in place** (`ProductCategoryPicker`), and it must stay that way. It was
free text (which made the column useless as data), then a Material `DropdownButtonFormField` — which
fixed the data but opens as a menu sized to its longest item, so twelve rows became a slab covering most
of the screen with no visible relationship to the field that opened it. **Do not go back to a Material
dropdown for a list this long.** The bottom sheet `ShopCategorySheet` uses is still right for *its* job
— four rows each carrying two lines of explanation — so the two pickers differing is deliberate.

That dropdown left a bug worth recognising by shape: `DropdownButtonFormField` renders the collapsed
value by **re-using the selected menu row's child**, so a `prefixIcon` plus an icon inside each
`DropdownMenuItem` painted the glyph twice. Any control with both a leading adornment and a rich
selected-item widget has this trap.

`ProductCategory.tryFromCode` returns **null** for an unrecognised code (unlike `ShopCategory.fromCode`)
so a pre-000006 free-text row opens the picker empty and forces one deliberate pick rather than being
silently filed under "Смеси".

**The price field carries a "сум"/"so'm" suffix, not a currency glyph** — it showed
`CupertinoIcons.money_dollar`, which names the wrong currency for every shop this app has.

### Account deletion (`DELETE /api/me`)

**Google Play requires it.** Any app that lets someone create an account must let them delete it from
inside the app, and must publish a web page describing the same thing for people who have already
uninstalled. The web half does not exist yet and is on the §11 list; the in-app half is built.

- **It is a hard delete.** The soft version — a `deleted_at` that hides the row — keeps the analytics
  tidy and makes "undo" possible, and it also means the user asked you to erase their phone number
  and you kept it, which is the one thing the policy exists to prevent. There is nothing worth
  keeping either: the account is a name, a phone number and a Telegram chat id.
- **One statement, because the schema cascades.** The shops go and each shop takes its products, so a
  deleted owner's pins leave the map in the same transaction. That is also why there is **no "delete
  your shops first" check** — making someone dismantle their account by hand before they may close it
  is an obstacle, and Play treats a deletion path with obstacles in it as no deletion path at all.
- **`DeleteUser` is `:exec`, not `:execrows`,** and deleting twice is a success. The caller is asking
  for a state, not an event; a row that was already gone means they got what they wanted.
- **The token outlives the account by exactly one request.** There is no revocation list, so the JWT
  is still a valid signature — what stops it is `RequireAuth`'s existence check, which answers 401
  `account_deleted` on the next request and is the code the app wipes its storage on. Pinned by
  `TestTheTokenStopsWorkingTheRequestAfterDeletion`.
- **Server first, phone second** (`AuthController.deleteAccount`). Wiping local storage before the
  request throws away the token the request needs; wiping it after a *failed* request signs the user
  out of an account that still exists, with no session to try again with. A failure leaves everything
  exactly as it was.
- **`isDeletingAccount` is a separate flag from `isLoading`.** `isLoading` draws the "open Telegram
  and share your number" overlay, which is the wrong thing to show someone who just asked to be
  deleted.
- The row lives in **its own card below the menu**, not as one more row inside it — the same split
  `MyShopsScreen` makes between managing and destroying. `DestructiveConfirmDialog`
  (`core/widgets/`) is shared with shop deletion: cancel first and visually heavier, confirm red on
  the right, and a body that names what disappears. **Don't hand-roll a second one.**

---

## 9. Traps and hard-won lessons

**Telegram — three load-bearing guards in `handleUpdate`/`handleContact`. Do not remove any.**

1. **`Contact.UserID == From.ID`.** The phone number *is* the identity here, and the "share contact"
   button is not the only way a `Contact` reaches the webhook — Telegram lets you forward any
   address-book entry, and the update looks almost identical. Without the check, anyone with a victim's
   number saved could log in as them and get a long-lived JWT.
2. **`recover()` plus a nil-check on `Message.From`.** Go has no per-goroutine crash isolation, so an
   unrecovered panic in this loop takes the HTTP server with it — and `From` is genuinely nil for
   channel posts and anonymous group admins, which every branch below dereferences.
3. **Row-not-found is `errors.Is(err, pgx.ErrNoRows)`, never a substring match.** It compared
   `err.Error()` to `"no rows in result set"`, which breaks silently if pgx rewords it and — worse —
   reads any *other* error containing "no rows" as "this user doesn't exist", sending the flow into
   `CreateUser`.

**`shrinkWrap: true` is a network decision, not a layout convenience.** A shrink-wrapped
`GridView`/`ListView` has to measure its own height, and the only way to do that is to lay out
**every** child — so `ShopProductsScreen`'s 100-product Универсальный catalogue mounted 100
`ProductTile`s at once, and each one's `Image.network` fired the moment it mounted. Down an ngrok
tunnel (India region, 204ms round trip) that is 100 requests and several megabytes ahead of anything
else on the connection.

**The symptom was not slow images. It was that saving a price failed.** The `PUT` queued behind the
image backlog, never got out inside its own 10-second timeout, and surfaced as
`Не удалось сохранить. Проверьте подключение` — on a phone whose connection was demonstrably fine,
since every other request worked. It then **fixed itself after ~30 seconds**, once the images landed
in Flutter's in-memory `ImageCache` and stopped competing, which is the shape of bug nobody believes
is real. The founder found it by noticing the correlation with image loading; two hypotheses tested
before that (R8 mangling Tink under `flutter_secure_storage`, and an empty template `unit` causing a
silent early return) were both wrong and both falsifiable in a minute — `stores_repository` calls the
same `getToken()` and worked, and `templates_test.go` already asserts `Unit != ""`.

**The tell was in ngrok's request log: no `PUT /api/products/…` appeared at all**, so the request
died on the phone rather than in Go. That log is the instrument for this whole class of bug —
`curl -s "localhost:4040/api/requests/http?limit=300"` gives every method, path and status, and
**which requests are *absent* is usually what localises the fault.** It was decisive twice in one
day (§9, the deep-link length bug, and this one), while the app's own error message was misleading
both times.

The fix is `ProductSliverGrid` inside a `CustomScrollView`, which builds only what is on screen, so a
catalogue of any size costs one screenful of requests. **`shrinkWrap` survives for the map's shop
sheet**, which is a `SingleChildScrollView` inside a bottom sheet and cannot become a
`CustomScrollView` as cheaply — it shows only *priced* products, so it is harmless while catalogues
are empty and becomes the same bug the day a shop prices all 100. Fix it there before that matters,
not after.

Two things were also wrong with how this reported itself, and both are fixed: a `TimeoutException`
now has its own `timeout` code ("нажмите «Сохранить» ещё раз") instead of falling through to a
default that blames the user's connection, and `ProductsController._mutate` **logs** the real
exception. It used to store it in `ProductMutationException.message`, which nothing renders — the
actual error existed, in a variable, and no human could see it.

**A session id has to fit inside a Telegram deep link, and the limit is 64 characters.** The
`start=` parameter of a `t.me` link accepts **1–64 characters from [A-Za-z0-9_-]**, and going over
does not produce an error — Telegram **drops the parameter**, opens the bot chat, and sends no
`/start` at all. Every symptom then points away from the cause: the link opens, the bot appears, the
user presses START by hand, the backend logs `pressed /start directly without a Flutter link` as
though they had found the bot themselves, and the app polls a session nothing will ever complete
until it reports `Сессия истекла`.

This was introduced by the hardening pass itself. Session ids went from 4 random bytes to 32 for
entropy — correct — but hex doubles 32 bytes into **64 characters**, and the `sess_` prefix made
**69**. The old 4-byte id was 13 characters and fit, so login worked before the change and broke
silently after it, on phones only.

The fix is **base64url, not fewer bytes**: `base64.RawURLEncoding` spells the same 32 bytes in 43
characters (48 with the prefix) and its alphabet is exactly the set Telegram permits. The entropy is
unchanged — it is a shorter spelling of the same 256 bits. `RawURLEncoding` rather than the padded
form because `=` is not in Telegram's allowed set. Pinned by
`TestSessionIDFitsATelegramDeepLink`, which checks the length *and* the alphabet, because the length
is a consequence of two decisions made in different places (how many bytes, and how they are encoded)
and either one moving breaks login everywhere at once.

> Opening a browser before Telegram is **normal and not a symptom.** A `t.me` link is an ordinary
> https URL, so Android hands it to the default https handler; Telegram claims it as an App Link and
> the hop resolves through. The payload survives that hop. This is the documented degradation path —
> a phone without Telegram lands on Telegram's web preview instead of failing — and it is why §5 uses
> the `https://t.me/` form rather than the `tg://` scheme.

**Android 11 made other apps invisible, and `url_launcher` silently depends on the manifest saying
otherwise.** From API 30 an app cannot resolve an intent against a package it has not declared an
interest in, and `canLaunchUrl` works *by* resolving the intent — so with no `<queries>` block for
`VIEW`+`https`, it returns **false for every https URL**, with Telegram installed and a browser on
the phone. `startTelegramLogin` gated the deep link on it and threw
`"Telegram application is not installed"`, which named the wrong cause and sent the founder hunting
for the bot by hand. `targetSdk` is 36, so it applied to every shipped build; it cannot reproduce on
a desktop run and did not reproduce on the emulator, because login was never attempted there.

**The diagnosis came off the server, not the app.** ngrok's request log showed two
`POST /api/auth/init` and **zero** `POST /api/auth/status` — the throw sat between the init call and
the start of polling, so "no status polls at all" localised it to those four lines. Nothing in
logcat mentions package visibility. When a network-shaped feature fails with no error, read which
requests were *not* made.

Two fixes, and the second matters on its own: the manifest now declares `VIEW`+`https` **and**
`DIAL`+`tel` (the shop sheet's call button is the same trap one screen over), and the gate is gone —
`launchUrl`'s own return value is the real signal. `canLaunchUrl` was answering "can anything here
open https", which is not the question: a `t.me` link is an ordinary https URL, so a phone *without*
Telegram opens Telegram's web preview rather than failing. That graceful degradation is precisely why
§5 uses the documented deep-link format instead of the `tg://` scheme, and the gate was throwing it
away.

**Schema/binary mismatch.** There was a `mustMatchSchemaVersion` startup guard and it was
**deliberately removed** — catching a stale binary belongs in CI/CD, not in a runtime check the app
carries. Don't re-add one. Recognise the shape instead: migration 000006 dropped `products.article`
while a server started an hour earlier still selected it. Every `GET /api/shops/{id}/products` returned
500, `/health` answered 200 the whole time because it only pings the pool, and the app showed a generic
error with a retry button that could not possibly help. **When an endpoint fails for no reason the code
explains, check the age of the server process before reading the code:**
`ps -eo pid,lstart,cmd | grep cmd/api` against the mtime of `db/*.sql.go`.

**`Provider.of<T>(context)` defaults to `listen: true`, and provider *asserts* if that is read outside a
build.** Not a performance nit — a crash. `add_store_screen.dart` had
`AppLocalizations get _strings => Provider.of<LanguageProvider>(context).strings;`, so every tap handler
touching `_strings` threw before doing anything, and the category tile looked like a dead button while
the location tile (which never reads `_strings`) worked fine. Any `_strings`-style getter read from a
callback must pass `listen: false`.

**A `RefreshIndicator` child that isn't a scrollable is broken twice over, and both failures are
silent.** It builds a `Stack` whose child gets *loose* constraints and `AlignmentDirectional.topStart`,
so any shrink-wrapping child renders in the **top-left corner**; and since the indicator only drives a
scrollable, pull-to-refresh does nothing at all. The fix is `LayoutBuilder` → `SingleChildScrollView`
(with `AlwaysScrollableScrollPhysics`, or content that fits exactly has nothing to overscroll and the
gesture is never recognised) → `ConstrainedBox(minHeight: viewport)` → `Center`. **Any full-page empty,
error or loading state under a `RefreshIndicator` must go through that shape.** The old spinner looked
fine only by accident: `Center` expands to fill a bounded box, so it escaped the alignment trap without
ever being scrollable.

**An `IndexedStack` builds every tab and paints one, so a screen behind a tab has no "I am visible"
signal and `initState` runs once for the life of the app.** The map fetched its shops from that one
`initState`, so a load that failed left «Не удалось загрузить магазины» on screen permanently, with
no retry control — and **restarting the app did not clear it**, because a restart put a fresh failing
fetch in the same place. That last part is what made it look like corrupted state rather than a live
failure. Two fixes, and both are needed: the shell passes `isActive: index == mapIndex` so
`didUpdateWidget` can catch the false→true edge, and `StoresController.refreshStoresIfStale()` decides
whether that edge costs a request. **The banner also got a «Повторить»** — an automatic retry that
only fires on a tab switch is not something a user should have to guess at.

> **`build()` running is not a visibility signal under `IndexedStack`, and neither is
> `didChangeDependencies`.** If a future screen needs one, pass a bool down the way the map does, or
> reach for `VisibilityDetector` — do not infer it.

**A `notifyListeners()` from `didUpdateWidget` (or `initState`) is "setState() called during build".**
Both run inside the build phase, so notifying a `ChangeNotifier` there marks listeners dirty in the
middle of a build already under way — and `MapScreen` is one of that controller's listeners. The
repository call is async, but `loadStores()` sets `_isLoading = true; notifyListeners();` *before* its
first `await`, so the notify happens synchronously. `addPostFrameCallback` is the fix, and it is why
`_syncShops()` is a method rather than one line at each call site.

**A dialog whose text is hardcoded while its API pretends otherwise cannot be caught by anything but
reading it.** `ProfileScreen._showErrorDialog(String message)` took a message, logged it, and then
rendered `errorDialogTitle` + `errorDialogInstructions` — the *login* strings, «Что-то пошло не так /
Проверьте, что Telegram установлен». So a failed account deletion told the user to check their
Telegram installation, and sent the founder hunting for a Telegram problem that did not exist. The
analyzer cannot see this: `message` *was* used, in the `debugPrint`, so it was not even an unused
parameter. It now takes `title` and `body` from the caller, with `detail` as the log-only technical
string. **When a widget's copy is fixed but its constructor implies otherwise, the second caller is
what discovers it** — there is no earlier signal.

**A `Column` inside a fixed-height card fails by overflowing, not by scrolling** — silent in release, a
striped bar in debug. Adding a line to the VIP card meant raising `cardHeight`.

---

## 10. Design system

**Visual tokens live in `core/constants/app_theme.dart` (`AppRadius`, `AppShadows`, `AppMotion`) plus
the ramp in `app_colors.dart` (`hairline`, `surfaceMuted`, `trackGrey`, `textFaint`, `primarySoft`,
`primaryTint`, `success`/`successSoft`, `danger`/`dangerSoft`, `warning`/`warningSoft`).** New UI pulls radius, shadow
and colour from these rather than inlining hex codes — before they existed, nine different corner radii
and about nine ad-hoc greys were in use simultaneously, which is what made screens look unrelated to one
another. The scale is deliberately short: radius `xs 8 / sm 14 / md 20 / lg 28`; shadows `card`
(barely-there lift) / `raised` (content cards that must separate from the page) / `floating` (nav bar,
sheets, map overlays) / `accent(colour)` (the glow under a primary button).

**Brand orange is reserved for primary actions, active state and highlights.** Surfaces are
white/`surfaceMuted` with `hairline` borders and dividers. The one exception is "Цена не указана" — see
§8.

**`AppColors.background` is `0xFFEFF1F5`, deliberately a real step below white** and not the near-white
it used to be. White cards on a near-white page had nothing separating them but a shadow, and a shadow
soft enough to look premium is too soft to do that alone — the contrast has to come from the surface
underneath (roughly iOS's `systemGroupedBackground`). It is a token, so it darkens every screen at once,
and `main.dart`'s `scaffoldBackgroundColor` references the token rather than repeating the literal. **If
the app ever looks too grey, this one value is the dial.**

`warning`/`warningSoft` were added for the middle state of the price badge — deliberately not
`starYellow`, which is bright enough to read as a highlight and is already spoken for by ratings.

`trackGrey` (`0xFFE4E7EC`) is the one token deliberately **below** `background`. It is the groove a
white pill slides in, and the illusion only works if the track is recessed — a track lighter than the
page reads as a card sitting on top of it. `surfaceMuted` and `cardGrey` are both at or above the page,
which is why neither could be reused.

That makes it the token for **anything that must read as grey while sitting directly on the page**,
which is now the segmented control's track and the категории glyph boxes (§8). `cardGrey` is for a
grey block on a *white* surface and is invisible anywhere else — the categories tiles were `cardGrey`
until the panel behind them was deleted, at which point they read as white.

**Brand orange is not an accessible text colour on light surfaces** — `#FF6F00` is about 2.6:1 against
`primarySoft` and 2.8:1 against white, where WCAG AA wants 4.5:1 for body text. This is a brand-level
fact, not a per-widget one: white-on-orange primary buttons have the same ratio. It is accepted for
brand moments (the VIP card's shop name, "Цена не указана") and should not be reached for where a
number or a sentence has to be read carefully.

**All icons are Lucide** (`flutter_lucide`), one family, monochrome `textDark`. A `hugeicons` pass was
reverted and the package removed: it assembles an SVG string at runtime through `flutter_svg`, pulling
in three extra packages and hinting less crisply than a glyph font.

**Press feedback is `PressableScale` (`core/widgets/pressable_scale.dart`), not an ink ripple**, on the
category tiles and the add-store picker tiles. A ripple spreads *inside* the shape, so on a large
bordered tile it is a faint grey wash in a box that never moves — precisely why those controls were
reported as feeling dead. Scaling moves the whole control. `_FormTileSurface` pairs it with an
`AnimatedContainer` that deepens the fill while the pointer is down, and observes the press through a
`Listener` rather than a second `GestureDetector`, since two recognisers on one subtree is how a tap
starts getting eaten.

**Every "nothing here" screen is `EmptyStateView` (`core/widgets/empty_state_view.dart`)** — Заявки,
Сообщения, Уведомления, the my-shops list, the category browse. **Two nested layers, and the inner one
is white-plus-shadow rather than a second tint**: two tints this pale are indistinguishable against an
off-white page, so the separation must come from value, not hue. Two conventions it encodes: a screen
behind a nav tab uses **that tab's own glyph**, so arriving somewhere feels like arriving at the thing
you tapped; and the `badge` ("Скоро") separates an *unbuilt* screen from a merely empty one.
`iconColor`/`iconBackground` exist so a load failure can be danger-coloured without inventing a
different layout. **Don't hand-roll another.**

### Do not change without being asked

- **`floating_bottom_nav_bar.dart`.** It was once reworked into a translucent `BackdropFilter` glass bar
  and the founder explicitly asked for the original back, exactly as it was — opaque white, 76px tall,
  filled orange gradient pill for the active tab. Don't "modernise" it again.
- **No section containers on the home feed — none, and the one exception is gone.** An earlier pass
  wrapped every section in a white panel and the founder had it removed; Категории kept one for a
  while, on the reasoning that its small tinted tiles needed a surface behind them or they read as
  loose objects. On 2026-08-18 the founder had it removed too. **Moving the white surface onto the
  individual tiles was tried as part of that and rejected in the same breath** — a white card round a
  grey box is two nested frames on a 64px tile — so the answer to "the tiles look loose" turned out to
  be that they do not (§8). Sections are separated by whitespace alone (26px).
- **`SectionHeader` passes no action on any section.** The VIP carousel loops endlessly, the categories
  grid pages through all twelve, and Лучшие предложения is a top-N — in every case the link would lead
  somewhere that doesn't exist. `actionLabel`/`onAction` stay on the widget for a section that one day
  genuinely has more to show. **Don't re-add one with an empty `onAction: () {}` to make the row look
  complete** — that is exactly what all three used to do.
- **`DevicePreview` is development-only and has now been removed and restored twice. Leave it.**
  It draws the app inside a phone frame so `make desktop` shows real phone proportions rather than
  the app stretched across the window. It was deleted once the `domix` emulator worked, on the
  reasoning that a real device beats a picture of one — and that was wrong in a way worth recording:
  **the emulator is a real phone running a debug build, and a debug build interprets Dart rather than
  running compiled code.** Scrolling stutters there, so it is the wrong place to judge a layout, and
  the founder lost the one smooth phone-shaped surface they had. The two are not substitutes. The
  emulator is where the map exists; the desktop is where layout work is comfortable.
  `enabled: !kReleaseMode && !MapConfig.isSupportedPlatform` now scopes it to desktop, since on a
  phone the device already *is* the frame and wrapping a 1080x2400 screen in a picture of a smaller
  one helps nobody. `MediaQuery.withNoTextScaling` stays the inner of the two wrappers in
  `MaterialApp`'s `builder` slot — **delete the DevicePreview half before release, not that one.**

---

## 11. Shipping to Google Play

**The app ignores the phone's font-size setting** — `main.dart`'s builder wraps everything in
`MediaQuery.withNoTextScaling`. This is a deliberate trade, not an oversight. The layout is built on
fixed card heights (`ProductTile.height` 208, `VipShopsCarousel.cardHeight` 232), so scaled text has
nowhere to go: measured on a 360dp phone **with a real proportional font**, the VIP card overflows at
scale **1.15** — Android's "Крупный", one notch above default — and the product tiles at 1.5. The
honest fix is cards that size to their content; if that ever gets built, **delete the wrapper rather
than raising the constants**. The cost is an accessibility one and the founder accepted it knowingly.

> **Measure text overflow with a real font loaded.** `flutter test` draws every glyph as a full em
> square, so Cyrillic comes out roughly twice its real width and the harness invents overflows that do
> not exist — an audit run that way reported width problems at 320dp and 360dp that vanished under
> `FontLoader` with a real TTF. Only the *font-scale* findings survived. Load one before believing a
> number: `FontLoader('Roboto')..addFont(...)` over any system TTF with Cyrillic.

**A custom `bottomNavigationBar` must inset itself.** Flutter's own `BottomNavigationBar` adds
`MediaQuery.padding.bottom`; `FloatingBottomNavBar` is hand-rolled and did not, so it was laid out
flush with the physical bottom of the screen and its lowest 48px sat behind the three navigation
buttons — labels covered, touch targets swallowed. It now adds `MediaQuery.viewPaddingOf(context)
.bottom`. **viewPadding, not padding**: `padding` collapses to zero while the keyboard is open, which
would drop the bar into the system buttons for as long as anyone is typing.

**Portrait is locked** in `main()`. Every screen is a vertical feed, a map or a form, and the VIP
carousel alone is taller than a landscape viewport.

### Android config — all of it was `flutter create` placeholder

| | was | is |
| --- | --- | --- |
| `applicationId`, `namespace` | `com.example.frontend` | `app.domix` |
| `android:label` | `frontend` | `Domix` |
| launcher icon | the Flutter logo, no adaptive icon | the Domix pin, legacy + adaptive + monochrome |
| release signing | the debug key | `android/key.properties`, gitignored |

**The launcher icon is an adaptive icon, and the foreground's size is the load-bearing part.**
Android 8 stopped drawing an app icon as a fixed picture and started masking two layers itself, so
the launcher decides whether Domix is a circle, a squircle or a rounded square. A single flat PNG
still installs and the system pillar-boxes it inside a white rounded square, which is what an app
looks like when nobody set this up. `mipmap-anydpi-v26/ic_launcher.xml` declares a flat
`@color/ic_launcher_background` (`#F26B21`, sampled from the founder's artwork rather than copied
from `AppColors.primaryOrange` — the two are close but not equal) plus the white pin as the
foreground and, unchanged, as the Android 13 `<monochrome>` layer.

The foreground layer is 108dp but only the central **66dp** survives every mask, and launchers pan
the rest during animations — a glyph drawn to fill its canvas gets clipped on exactly the devices
nobody tests on. The pin is drawn at 560/1024 of the canvas, which puts its furthest point 280px from
centre against the 313px the safe circle allows. Regenerating from a new source means redoing that
arithmetic, not just resizing.

The source artwork is **`domix_icon.png` at the repo root**, untracked and referenced by nothing —
every shipped icon is a generated PNG under `android/app/src/main/res/`, so renaming or deleting it
breaks no build. It is only needed to regenerate, and it carried a `TILE 1 — ON` caption in its
bottom 62px that was cropped off before use.

`applicationId` is **permanent from the first upload** — it is the listing's primary key, so changing
it later means publishing a different app and losing every install and review. Play also rejects
`com.example.*` outright. It needs **at least two dot-separated segments**, so a bare `domix` is not a
legal value; `app.domix` is the founder's choice — no country and no platform, for something that may
become a website and leave Uzbekistan. It is *not* the conventional reverse-DNS shape (`uz.domix`
would be), and that is fine: Android only requires two segments and a legal Java package name, and
nothing checks that the domain is yours. `MainActivity.kt` lives in `kotlin/app/domix/` to match, and
`userAgentPackageName` on both maps says the same thing. **Changing it again after the first upload is
not possible**, so it is settled now.

The release build reads the upload key from `android/key.properties` (see
`key.properties.example`) and **falls back to debug signing with a warning when it is absent**, so a
checkout without the key still runs. That fallback cannot ship by accident: Play refuses a
debug-signed artifact. Generate the keystore once and back it up off the laptop — without it there is
no way to publish an update to the installed app:

```bash
keytool -genkey -v -keystore ~/domix-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias domix
```

### Testing on a real Android phone

The reference device is a **Redmi Note 9S** (`curtana`, MIUI). Two setups, each done once.

**On this Arch laptop:** `adb` cannot talk to a USB device without udev rules and group membership.
Without them the phone shows as `no permissions` or does not appear in `adb devices` at all.

```bash
sudo pacman -S android-udev
sudo usermod -aG adbusers ayzrixsiev
```

**Then log out and back in.** A login session captures its group list at start and cannot pick up a
new one, so every process — `adb` included — keeps running without `adbusers` until the session is
replaced. The tell is `id -nG` and `groups` disagreeing: the first reads the group file, the second
reports the live session. `usermod` prints nothing on success, so the group file is the thing to
check, not the exit code.

**On the phone — MIUI needs more than stock Android.** Developer mode is Settings → About phone →
tap **MIUI version** seven times. Then in Developer options:

| toggle | needed for |
| --- | --- |
| **Отладка по USB** | the standard one |
| **Установка через USB** | MIUI-only, and the one that blocks `adb install`. Requires a signed-in Mi account and working internet on the phone — it verifies online |
| Default USB configuration → **Передача файлов (MTP)** | "Только зарядка" blocks adb on several MIUI builds |
| Отладка по USB (настройки безопасности) | **not** needed for installing. It is for simulating input and granting permissions over adb. Leave it off |

A correctly attached phone reads `device` in `adb devices -l` — not `unauthorized` (the on-screen
fingerprint prompt was not accepted) and not `no permissions` (the group step did not take).

**`make apk-test` is what to install** (§4). The app it produces still calls the ngrok tunnel, because
`API_BASE_URL` is compiled in — so **ngrok and `go run ./cmd/api` must both be up or every screen is
empty**. The phone does not need to share the laptop's wifi; the tunnel is public, so mobile data is
fine. Once installed the app is standalone: no `flutter run` attached, no hot reload, and a change
means rebuild and reinstall.

**Two bugs have now been found that can only appear here**, which is the argument for doing this
early rather than at release: Android 11 package visibility breaking every `url_launcher` call (§9),
and R8 (§4, `apk-test`). Neither reproduces on a desktop run, and neither reproduced on the emulator.

### The two irreplaceable files, and how they are backed up

`~/domix-upload-key.jks` and the repo-root `.env` are the only files here that cannot be regenerated:
losing the keystore means never shipping an update to the installed app, and `.env` holds `DB_URL`,
`TELEGRAM_BOT_TOKEN` and `JWT_SECRET`. `scripts/secrets.sh` packs both (plus `key.properties`) into
`secrets.vault.enc` — AES-256, PBKDF2, 600k iterations:

```bash
./scripts/secrets.sh backup    # pack + encrypt into secrets.vault.enc
./scripts/secrets.sh restore   # decrypt back into place; never overwrites an existing file
./scripts/secrets.sh list      # what is inside, without unpacking
```

**The vault is deliberately NOT in git, and the script's own output saying to commit it is stale.**
It was committed once (`f2ee5ff`, 2026-08-17) and the founder had it removed the same day and the
push force-rewound — the repo is for code. **Do not re-add it, and do not "helpfully" commit it after
running `backup`.** The encryption is what makes committing it *safe*, not what makes it *desirable*;
those are different questions and only the first one was ever settled here.

**Committing the files as plain text was asked for and rejected, and the reason is not that the repo
is public** — it is private today. It is that git history is permanent and retroactive: a secret
committed once stays in every clone, fork and backup forever, and `git rm` does not remove it. Making
the repo public later, adding a collaborator, or handing over a laptop would each expose all of it at
once, years after the commit. A leaked `JWT_SECRET` can be rotated at the cost of signing every user
out; **a leaked `.jks` cannot be rotated at all.**

So the vault has to live somewhere that is neither this laptop nor this repository — Google Drive, a
USB stick, or a password manager's file attachment. **It is a snapshot, not a mirror:** re-run
`backup` after every `.env` change, and `DB_URL` and `WEBHOOK_URL` both change the day the backend
leaves ngrok for a real host.

The passphrase is the one thing that is not in the repo and cannot be recovered. `restore` refuses to
clobber a file that already exists, so restoring onto a working machine cannot silently replace a
current `.env` with an older one — a failure that would surface much later as "everyone got logged
out".

### Builds go through the Makefile

`--dart-define-from-file` is Flutter's only way to compile config into a binary, and there is no
avoiding it — what was wrong was one env file doing two jobs and a long flag typed by hand.

| file | committed? | holds |
| --- | --- | --- |
| `env.json` | no, gitignored | the developer's own backend (an ngrok tunnel) |
| `env.prod.json` | **yes** | the production API address and the Yandex MapKit public key |

`env.prod.json` is in git deliberately. **Nothing in a `--dart-define` can be secret** — the values
become plain constants in the binary and come out of a shipped APK with a hex editor — so the file
can only ever hold public facts, and keeping it in git is what makes a release reproducible. Anything
that must stay private belongs behind an authenticated endpoint.

`make release` runs `guard-prod` first and refuses to build on a placeholder `REPLACE_ME`, on an
`http://` API address, or with `android/key.properties` missing. All three of those fail *silently*
otherwise — the app installs and every screen sits on a spinner, or Play rejects the upload.

### Maps: Yandex MapKit Lite, replacing Mapbox raster tiles

**The map is drawn natively by Yandex MapKit, not by us over tiles.** It was `flutter_map` painting
OpenStreetMap and then Mapbox `{z}/{x}/{y}` images with our own pins on top; Yandex's licence forbids
pulling their tiles outside their SDK, so there was no "swap the URL" version of this move.

**Why it was worth rewriting the map feature for.** The two providers meter completely different
things, and the numbers most comparisons quote belong to the product we were *not* using:

| | metered by | free each month |
| --- | --- | --- |
| Mapbox Static Tiles (what we had) | individual tile requests | 200 000 requests |
| Mapbox Maps SDK | monthly active users | 25 000 MAU |
| **Yandex MapKit Lite (now)** | **monthly active users** | **25 000 MAU** |

Per-request billing shrinks as people pan — one person opening the map costs tens of requests, so
the budget was in map *sessions* rather than users, and it needed a billing alert because Mapbox has
no hard cap. MAU billing does not move when somebody drags the map.

The Free licence's conditions are ones we already meet — free to download, no turn-by-turn
navigation, no monitoring or dispatch. **If any of those three changes, the licence has to be
revisited before the code is.**

**Lite, not the full package.** `yandex_maps_mapkit_lite` is the free-licence one: map, map objects,
camera, user location. The full `yandex_maps_mapkit` adds search, routing and panoramas — the paid
parts, and ones we do not use. Address search and reverse geocoding **stay on Nominatim** and were
untouched by the move.

**`domix_map.dart` is the entire boundary.** `DomixMap`, `DomixMapController` and `MapPin` are all
the screens see; nothing outside that file imports the SDK, which is why swapping the provider
touched two screens rather than twenty. Keep it that way.

**Pins are still Flutter widgets, and that is the finding that made this cheap.** A native map draws
bitmaps, not widgets — but `ViewProvider` takes a widget *builder*, lays it out off-screen against a
`RenderRepaintBoundary` and hands MapKit the raster. So `ShopMarker` survived unchanged. Two
consequences, both handled in `DomixMap` and both silent if forgotten:

- **No `InheritedWidget` reaches a pin.** ViewProvider builds under a bare `MediaQuery` +
  `Directionality` — no `Theme`, no `Provider`, no `DefaultTextStyle`. A pin that calls
  `Theme.of(context)` throws off-screen and nowhere else.
- **A `GestureDetector` inside a pin does nothing** — a picture cannot be tapped. Taps arrive through
  `placemark.addTapListener`, which is why `MapPin.onTap` is a field. `ShopMarker.onTap` is now
  nullable and is always null on the map.

**`MapPin.visualKey` does two jobs and must capture every visual difference.** It decides when the
pin list is rebuilt, *and* it is MapKit's raster cache key — so forty identical "универсальный,
зелёный, −4%" pins are laid out once between them. A key that misses a difference caches the wrong
bitmap; a key that includes the shop's name defeats the cache entirely.

**MapKit downloads nothing until `mapkit.onStart()` is called, and every symptom points somewhere
else.** The map surface comes up without it: the GL context is created, the grey grid and the Yandex
logo draw, the camera moves, `logcat` shows `Attach new plugin to engine`, `Init engineId` and a
successfully `Chosen EGL config` — and not one error. It reads exactly like a rejected API key. The
one signal that separates them is in the **Yandex dashboard: zero requests**. A rejected key still
counts as a request; an unstarted MapKit never makes one, so `0 из 1000 запросов` means the network
layer was never started, not that the key is bad. Ping the tile host from the device
(`adb shell ping core-renderer-tiles.maps.yandex.net`) to take the network out of the question first.

`onStart`/`onStop` live on the **global `mapkit` singleton**, not on a map, so they cannot just sit in
one widget's `initState`/`dispose` — `location_picker_screen` can be pushed over `map_screen`, and the
second map's `dispose` would stop the network layer under the first one, which is still on screen.
`domix_map.dart` therefore keeps a **count of mounted maps** plus the app's foreground state, and
`_syncMapkitLifecycle()` reconciles the two; it no-ops when MapKit's state already matches, since
`onStart` is not documented as idempotent. The foreground half is not a nicety — MapKit keeps sockets
and caches warm while started, and `onStop` is documented for exactly "the application pauses and goes
to the background". The singleton also means `mapkit_factory.dart` must be imported separately:
`mapkit.dart` does not export it.

**MapKit holds listeners by weak reference.** Camera, input and per-pin tap listeners are all fields
on `_DomixMapState`, never locals. Anything only the native side points at is collected on the next
GC and the callbacks silently stop — a map that works for ten seconds and then ignores the camera,
with nothing in any log.

**Three things in `android/` exist only because of MapKit, and each one failed in a way that named
neither Yandex nor the real cause:**

- **`compileSdk` is forced to 36 for every plugin subproject** (`android/build.gradle.kts`). Plugins
  pin their own, and these two disagree: MapKit compiles against 35, while
  `flutter_plugin_android_lifecycle` — which MapKit itself depends on — requires 36+. Two
  constraints on packages we do not own, and the fix has to be ours. **The placement is
  load-bearing twice over:** `afterEvaluate` rather than `plugins.withId` (withId fires as the
  plugin is *applied*, and the rest of its build file then sets 35 straight back), and registered
  inside the *first* `subprojects` block, because the later one calls `evaluationDependsOn(":app")`
  and an `afterEvaluate` added after that throws `Cannot run Project.afterEvaluate(Action) when the
  project is already evaluated`.
- **`play-services-location`** is declared in `app/build.gradle.kts`. MapKit's location layer needs
  it and the plugin does not pull it in; without it the app compiles and dies at runtime.
- **Gradle's heap is capped at 2 GB** (`android/gradle.properties`) — see §4. Unrelated to MapKit
  except that MapKit is what made anyone build for Android often enough to notice.

**MapKit merges seven permissions into the manifest**, and they show up on the Play listing:
`ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_FINE_LOCATION`,
`WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE` — none of which we ask for, since we do
not use `createUserLocationLayer`. **Do not strip them blind with `tools:node="remove"`**: a native
SDK that checks for a permission it declared can fail at runtime, and that would only show up on a
device. `ACCESS_FINE_LOCATION` is the one that costs something concrete — Play makes you justify it
— and it is also the one we will want the day the map grows a "where am I" button.

**A Flutter upgrade will eventually break this.** The build already warns: *"Your app uses the
following plugins that apply Kotlin Gradle Plugin (KGP): yandex_maps_mapkit_lite. Future versions of
Flutter will fail to build."* Nothing to do today — it is Yandex's to fix — but if a Flutter upgrade
ever fails on Kotlin, this is why.

**What the move cost, all three worth knowing:**

- **`minSdk` went from 24 to 26** (Android 8.0). MapKit's floor, not ours — the build fails outright
  below it.
- **Building now needs JDK 21+.** The plugin ships class files at version 65 (Java 21) and javac 17
  cannot read them. The error names neither Java nor the JDK: `class file has wrong version 65.0,
  should be 61.0`.
- **The map no longer runs on desktop or web.** `flutter_map` was pure Dart; MapKit registers for
  Android and iOS only, so eyeballing the map on a Linux `flutter run` is over — it needs a device or
  an emulator. `MapConfig.isSupportedPlatform` keeps the *rest* of the app running there, with
  `MapUnavailablePanel` in the map's place instead of a crash on a missing plugin.

**Attribution is MapKit's job now.** The hand-rolled `_MapAttribution` pill is deleted, not moved:
it existed for OpenStreetMap's ODbL requirement, and MapKit draws Yandex's own logo and copyright as
part of the map surface. Adding ours back would credit the wrong party.

**Free tier or not, there is still no hard cap** — set a billing alert in the Yandex dashboard.

### Still open before release

Grouped by what actually blocks what. **Nothing below is in progress** — this is the list to work
through when the app goes to shop owners and then to Play. The first group is ordered: the closed
test runs on a calendar rather than on effort, and the vault takes ten minutes and removes the worst
outcome on the list.

#### Do these first — they gate everything else

1. **Copy `secrets.vault.enc` somewhere off this laptop.** The script has been run once and verified
   (`backup` then `list`, 2026-08-17), so the passphrase is known to work — but the vault was
   **removed from git by request** and no copy of it exists anywhere else, which leaves
   `~/domix-upload-key.jks`, the repo-root `.env` and `android/key.properties` on **one laptop and
   nowhere else**, exactly as before. Google Drive, a USB stick or a password manager's file
   attachment all close it; re-running `backup` does not, since it writes to the repo root. Write the
   passphrase on paper, off the laptop. See `KEYS-AND-ACCOUNTS.txt` at the repo root for the full
   inventory of what is irreplaceable, what is rotatable, and what only looks like a secret.
2. **Start the closed test.** A personal Play developer account cannot apply for production access
   until it has run a closed test with **~12 testers opted in for 14 continuous days**. That is a
   calendar, not a task — start it and do everything else while it runs.
3. **Get a production domain with HTTPS and a host for the backend.** `env.prod.json` still says
   `https://REPLACE_ME` and `make release` refuses to build until it doesn't. Android 9+ blocks
   cleartext HTTP with no `usesCleartextTraffic` in the manifest, so an `http://` address would fail
   every request silently in release — the Makefile checks for that too. Nothing else on this list can
   be tested end to end without it.

#### Play policy — a listing is rejected without each of these

- **A public account-deletion web page.** The in-app path is built (§8), but Play requires a URL that
  works **without installing the app**, describing what is deleted and how to request it. One static
  page; it needs the domain above.
- **App access instructions.** Login goes through a Telegram bot, so a Google reviewer with no
  Telegram account hits the login wall and rejects the submission as broken. Fill in Play Console's
  **App access** section with a walkthrough and a screen recording. This is one of the most common
  rejections for phone-verified apps.
- **The Data Safety form.** Declare what is collected and why: name, phone number, Telegram chat id,
  and — the one that is easy to forget — **approximate location**, since a shop owner picks a point on
  a map. It must match what the app actually does; a mismatch found later is a policy strike, not a
  correction.
- **Justify `ACCESS_FINE_LOCATION`.** MapKit merges seven permissions into the manifest (§11 above)
  and this is the one Play makes you explain. **Do not strip them with `tools:node="remove"`** — a
  native SDK that checks for a permission it declared can fail at runtime, and only on a device.
- Content rating questionnaire, target audience, and a privacy policy URL — all Console forms, all
  needing the domain.

#### Code and build

- **Run `make apk` once the domain exists, with the emulator closed.** `make apk-test` covers most of
  it already (§4) and is what has actually been run on the Redmi; what `apk-test` cannot cover is the
  production address, which is the one thing `env.prod.json` carries that `env.json` does not.
  `android/app/proguard-rules.pro` now exists, and Flutter's Gradle plugin picks it up by filename
  with nothing to wire up (`FlutterPlugin.kt` sets `isMinifyEnabled = true` on the release build type
  and appends the file if it is there). **Writing the rules is not the same as knowing they are
  right.** R8 only runs for release: it deletes code nothing appears to call and renames what is
  left, deciding "nothing calls this" by reading the code — so anything looked up **by name at run
  time** is invisible to it, and Yandex MapKit's native layer does exactly that over JNI. The rules
  keep `com.yandex.**` whole, plus `androidx.security.crypto.**` (flutter_secure_storage builds its
  crypto reflectively — stripped, the release build silently cannot read its own stored JWT and every
  user appears logged out). The symptom of a wrong rule is a debug build that works forever and a
  release build with a blank map or an empty session, discovered after upload. `make apk` is also the
  only way to confirm the upload key signs a real artifact end to end; `gradlew :app:signingReport`
  has confirmed the config, not a build.

- **A Yandex MapKit API key in `env.prod.json`.** It says `REPLACE_ME` and `make release` refuses to
  build until it doesn't. The *development* key is already in `env.json` and working. From Yandex's
  developer dashboard, MapKit Mobile SDK, Free plan. Without one the map screens show
  `MapUnavailablePanel` instead of a map. Set a billing alert the day the key is created — the free
  tier has **no hard cap**.
- **Keep going on the device.** The map now draws (§3), so the items that were behind it are finally
  reachable: pin rasterization, the teardrop's anchor, a tap opening the sheet, the camera listener
  surviving a GC, and the location picker's address keeping step. §3 lists them in the order they
  would fail.
- **`shops.rating` is still a stored column nothing writes — the app now hides the star instead of
  printing it.** Every shop reads 0.0, and `⭐ 0.0` says "customers rated us zero out of five" where
  the truth is "nobody has rated us" — opposite meanings, and a shop owner opening the app saw the
  wrong one. The rule lives in **two getters and nowhere else**: `Shop.hasRating` and
  `HomeShopPreview.hasRating`, both `rating > 0`. Two because the home feed carries its own lighter
  model; they are documented as mirrors, because a star appearing on the map but not on the home
  screen would read as one of the two being broken. All three draw sites ask a getter
  (`home_shop_row.dart`, `vip_shops_carousel.dart`, `map_screen.dart`'s `_ShopMetaLine`) — so a
  `reviews` table lights the star up everywhere at once. **Each site drops its own separator with the
  star**: the VIP carousel hides the entire white pill (an empty badge reads as a failed load), and
  the map sheet hides the `_MetaDot` too, or the line would open with a bullet pointing at nothing.
  Inventing a number instead — defaulting to 5.0, or `?? 4.5` — was rejected: absence of a star says
  "no reviews" without claiming anything. It is no longer the VIP carousel's sort key —
  **membership there is sold, not earned**, so ranking by a quality signal was a lie about how the
  slot is decided *and* inert at 0.0; `ListVipShops` orders by `vip_until DESC`, the longest-running
  placement first. If the order ever needs picking by hand, that is a `vip_rank` column, not another
  proxy.
- **Pricing a hundred products costs ~500 taps.** Each price is: tap tile → push `ProductEditScreen`
  → tap field → type → save → pop. And under the 000013 rule an owner who stops at 80 of 100 publishes
  **nothing** — no badge, no Лучшие предложения, no index — so the drop-off is total rather than
  partial. Nothing about this stresses the system (100 requests over a week is not load); it is a
  human problem, and the fix is a quick-entry list where the keyboard stays up and Next jumps to the
  next unpriced row. **Deferred deliberately** — do it when a real shop owner gives up halfway, not
  before.
- **`ListShops` has no `LIMIT` and no bounding box**, so opening the map fetches every shop in the
  database. Irrelevant at 50–70 shops; revisit around 1 000.
- **`shop_basket_index` is a plain view, not materialized**, and its `basket` CTE is referenced twice
  — a materialization barrier, so postgres cannot push the category predicate down and every query
  touching it sequentially scans every template product row. `GET /api/home` pays that five times.
  Measured: ~3 ms per home request at 50 shops, 36 ms at 1 000, 175 ms at 5 000. **The axis that hurts
  is shop count, not user count.** Past ~1 000 shops the fix is a materialized view refreshed on price
  change or a cached home payload — **not** a bigger connection pool.
- **Delete `DevicePreview`.** The package in `pubspec.yaml`, the import and the `DevicePreview(...)`
  wrapper around `MultiProvider` in `main.dart`, and the outer half of the two-wrapper `builder` —
  keeping `MediaQuery.withNoTextScaling`. `enabled:` already keeps it out of a running release
  binary, so this is about not shipping a development dependency, not about correctness. It is here
  because it has been removed and restored twice (§10) — read that note before removing it a third
  time, since the emulator is not the replacement it looks like.

#### Infrastructure and operations

- **Database backups.** There is no `pg_dump` on any schedule. Every shop's catalogue is hand-typed by
  its owner and exists in exactly one place; losing it does not lose a demo, it loses work real people
  did. This ranks above every polish item on this list.
- **Nominatim** (address search, reverse geocoding) is still the free public instance: ~1 req/sec
  shared across every user, and no production traffic allowed. With 50 owners registering addresses at
  once the symptom is 429s and then a temporary IP block, which reads to them as "address search is
  broken" with nothing in the server's logs. Cheap mitigation first — cache repeated lookups and send
  a real contact `User-Agent`, which their policy requires — self-hosting later. The map itself moved
  to Yandex MapKit; this did not, and MapKit Lite has no search to move it to (that is the paid full
  package).
- **No error reporting.** When the app breaks on an owner's phone, nobody finds out. Even structured
  server logs plus a crash reporter would turn "it doesn't work" into a stack trace.
- **Nothing exposes `pool.Stat().EmptyAcquireCount()`.** That counter — requests that had to wait for
  a connection — is the only evidence that would justify changing `DB_MAX_CONNS`. Without it, any pool
  tuning is guessing. Ten lines behind a token-protected `/metrics`.
- **The glibc collation mismatch on the local database.** `domix_db` was created under glibc 2.43 and
  the OS now provides 2.44, so `CREATE DATABASE` from `template1` fails outright. The repair is
  `REINDEX DATABASE domix_db;` **and then** `ALTER DATABASE domix_db REFRESH COLLATION VERSION;` — in
  that order. Refreshing alone only silences the warning while leaving text indexes possibly sorted by
  the old rules.
- **CORS is still `Access-Control-Allow-Origin: *`.** Harmless for a mobile client (CORS is a browser
  rule) and deliberately left alone; it needs narrowing the day a web frontend exists.
- **No refresh token.** The user-existence check in `RequireAuth` covers deletion, but a *stolen*
  token belonging to a live account still works until it expires. Revoking one without deleting the
  account needs a `token_version` column bumped on logout.
- **`TELEGRAM_DEBUG` must stay off in production.** The firehose it prints contains real phone
  numbers. Same for `TRUST_PROXY`: only turn it on once something in front *always* rewrites
  `X-Forwarded-For`, since both ways of getting it wrong fail silently.
