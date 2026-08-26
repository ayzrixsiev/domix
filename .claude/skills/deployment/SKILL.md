---
name: deployment
description: >
  Releasing Domix to Google Play — Android build config, release signing and the upload
  keystore, the adaptive launcher icon, Yandex MapKit setup and its Android build
  requirements, testing on a real device, secrets backup, and the open list of things that
  still block a Play submission. Use when building a release artifact (`make apk`,
  `make release`), editing anything under `frontend/android/`, touching `env.prod.json`,
  `key.properties`, `proguard-rules.pro` or the app manifest, working on MapKit integration
  or its Gradle/JDK requirements, sideloading to a test phone, handling the keystore or
  `secrets.vault.enc`, or answering "what is left before we can ship".
---

# Shipping Domix to Google Play

Release- and Android-build-specific. Day-to-day feature work does not need it.

---

## Accessibility and orientation trades

**The app ignores the phone's font-size setting** — `main.dart` wraps everything in
`MediaQuery.withNoTextScaling`. Deliberate: the layout uses fixed card heights (`ProductTile.height`
208, `VipShopsCarousel.cardHeight` 232), so scaled text has nowhere to go. Measured on a 360dp phone
with a real proportional font, the VIP card overflows at scale **1.15** (Android's "Крупный", one notch
above default) and product tiles at 1.5. The honest fix is cards that size to their content; **if that
gets built, delete the wrapper rather than raising the constants.** The founder accepted the cost
knowingly.

> **Measure text overflow with a real font loaded.** `flutter test` draws every glyph as a full em
> square, so Cyrillic comes out roughly twice its real width and the harness invents overflows that do
> not exist. Load one first: `FontLoader('Roboto')..addFont(...)` over any system TTF with Cyrillic.

**A custom `bottomNavigationBar` must inset itself.** Flutter's own adds `MediaQuery.padding.bottom`;
`FloatingBottomNavBar` is hand-rolled and did not, so its lowest 48px sat behind the system navigation
buttons. It now adds `MediaQuery.viewPaddingOf(context).bottom` — **viewPadding, not padding**:
`padding` collapses to zero while the keyboard is open, which would drop the bar into the system buttons
for as long as anyone is typing.

**Portrait is locked** in `main()` — every screen is a vertical feed, a map or a form, and the VIP
carousel alone is taller than a landscape viewport.

---

## Android config

All of it was `flutter create` placeholder:

|                              | was                            | is                                        |
| ---------------------------- | ------------------------------ | ----------------------------------------- |
| `applicationId`, `namespace` | `com.example.frontend`         | `app.domix`                               |
| `android:label`              | `frontend`                     | `Domix`                                   |
| launcher icon                | Flutter logo, no adaptive icon | Domix pin, legacy + adaptive + monochrome |
| release signing              | the debug key                  | `android/key.properties`, gitignored      |

**`applicationId` is permanent from the first upload** — it is the listing's primary key, so changing
it later means publishing a different app and losing every install and review. Play rejects
`com.example.*` and requires two dot-separated segments, so a bare `domix` is not legal. `app.domix` is
the founder's choice: no country, no platform, for something that may become a website and leave
Uzbekistan. It is not conventional reverse-DNS and that is fine. `MainActivity.kt` lives in
`kotlin/app/domix/` to match, and `userAgentPackageName` on both maps says the same thing. **Settled —
do not change it.**

### The launcher icon

Android 8 masks two layers itself, so the launcher decides whether Domix is a circle, a squircle or a
rounded square; a single flat PNG installs and gets pillar-boxed inside a white rounded square.
`mipmap-anydpi-v26/ic_launcher.xml` declares a flat `@color/ic_launcher_background` (`#F26B21`, sampled
from the founder's artwork rather than copied from `AppColors.primaryOrange` — close but not equal) plus
the white pin as foreground and, unchanged, as the Android 13 `<monochrome>` layer.

**The foreground's size is the load-bearing part.** The layer is 108dp but only the central **66dp**
survives every mask, and launchers pan the rest during animations. The pin is drawn at 560/1024 of the
canvas, putting its furthest point 280px from centre against the 313px the safe circle allows.
**Regenerating from new artwork means redoing that arithmetic, not just resizing.** Source artwork is
`domix_icon.png` at the repo root — untracked, referenced by nothing, only needed to regenerate.

### Release signing

The release build reads the upload key from `android/key.properties` (see `key.properties.example`) and
**falls back to debug signing with a warning when it is absent**, so a checkout without the key still
runs. That fallback cannot ship by accident — Play refuses a debug-signed artifact. Generate once and
back it up off the laptop; without it there is no way to publish an update to the installed app:

```bash
keytool -genkey -v -keystore ~/domix-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias domix
```

### R8 and `proguard-rules.pro`

Flutter's Gradle plugin picks the file up by filename with nothing to wire up. **Writing the rules is
not the same as knowing they are right.** R8 only runs for release: it deletes code nothing appears to
call and renames what is left, deciding "nothing calls this" by reading the code — so anything looked up
**by name at run time** is invisible to it, and MapKit's native layer does exactly that over JNI. The
rules keep `com.yandex.**` whole, plus `androidx.security.crypto.**` (flutter_secure_storage builds its
crypto reflectively — stripped, the release build silently cannot read its own stored JWT and every user
appears logged out).

**The symptom of a wrong rule is a debug build that works forever and a release build with a blank map
or an empty session, discovered after upload.** `make apk-test` is what finds it before then.

---

## Build files: `env.json` vs `env.prod.json`

| file            | committed?     | holds                                                       |
| --------------- | -------------- | ----------------------------------------------------------- |
| `env.json`      | no, gitignored | the developer's own backend (an ngrok tunnel)               |
| `env.prod.json` | **yes**        | the production API address and the Yandex MapKit public key |

`env.prod.json` is in git deliberately. **Nothing in a `--dart-define` can be secret** — the values
become plain constants in the binary and come out of a shipped APK with a hex editor — so the file can
only hold public facts, and keeping it in git is what makes a release reproducible.

`make release` runs `guard-prod` first and refuses to build on a placeholder `REPLACE_ME`, on an
`http://` API address, or with `android/key.properties` missing. All three fail _silently_ otherwise —
the app installs and every screen sits on a spinner, or Play rejects the upload.

---

## Testing on a real Android phone

Reference device: **Redmi Note 9S** (`curtana`, MIUI). Two setups, each done once.

**On this Arch laptop** — `adb` cannot talk to USB without udev rules and group membership; without them
the phone shows `no permissions` or does not appear at all:

```bash
sudo pacman -S android-udev
sudo usermod -aG adbusers ayzrixsiev
```

**Then log out and back in.** A login session captures its group list at start and cannot pick up a new
one, so every process — `adb` included — keeps running without `adbusers` until the session is replaced.
The tell is `id -nG` and `groups` disagreeing: the first reads the group file, the second reports the
live session. `usermod` prints nothing on success, so check the group file, not the exit code.

**On the phone — MIUI needs more than stock Android.** Developer mode is Settings → About phone → tap
**MIUI version** seven times. Then in Developer options:

| toggle                                                | needed for                                                                                                                  |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Отладка по USB**                                    | the standard one                                                                                                            |
| **Установка через USB**                               | MIUI-only, and the one that blocks `adb install`. Requires a signed-in Mi account and working internet — it verifies online |
| Default USB configuration → **Передача файлов (MTP)** | "Только зарядка" blocks adb on several MIUI builds                                                                          |
| Отладка по USB (настройки безопасности)               | **not** needed for installing — leave it off                                                                                |

A correctly attached phone reads `device` in `adb devices -l` — not `unauthorized` (the fingerprint
prompt was not accepted) and not `no permissions` (the group step did not take).

**`make apk-test` is what to install.** The app it produces still calls the ngrok tunnel because
`API_BASE_URL` is compiled in, so **ngrok and `go run ./cmd/api` must both be up or every screen is
empty**. The phone does not need the laptop's wifi — the tunnel is public. Once installed the app is
standalone: no hot reload, and a change means rebuild and reinstall.

**Two bugs have been found that can only appear here**, which is the argument for doing this early:
Android 11 package visibility breaking every `url_launcher` call (root §8), and R8. Neither reproduces
on a desktop run or on the emulator.

---

## The two irreplaceable files

`~/domix-upload-key.jks` and the repo-root `.env` are the only files that cannot be regenerated: losing
the keystore means never shipping an update to the installed app, and `.env` holds `DB_URL`,
`TELEGRAM_BOT_TOKEN` and `JWT_SECRET`. `scripts/secrets.sh` packs both (plus `key.properties`) into
`secrets.vault.enc` — AES-256, PBKDF2, 600k iterations:

```bash
./scripts/secrets.sh backup    # pack + encrypt into secrets.vault.enc
./scripts/secrets.sh restore   # decrypt back into place; never overwrites an existing file
./scripts/secrets.sh list      # what is inside, without unpacking
```

**The vault is deliberately NOT in git, and the script's own output saying to commit it is stale.** It
was committed once (`f2ee5ff`, 2026-08-17), removed the same day and the push force-rewound. **Do not
re-add it.** Encryption is what makes committing it _safe_, not what makes it _desirable_ — different
questions, and only the first was ever settled.

Committing the files as plain text was asked for and rejected — not because the repo is public (it is
private) but because **git history is permanent and retroactive**: a secret committed once stays in every
clone, fork and backup forever, and `git rm` does not remove it. Going public later, adding a
collaborator, or handing over a laptop would expose all of it at once. A leaked `JWT_SECRET` can be
rotated at the cost of signing every user out; **a leaked `.jks` cannot be rotated at all.**

The vault must live somewhere that is neither this laptop nor this repository. **It is a snapshot, not a
mirror:** re-run `backup` after every `.env` change, and `DB_URL` and `WEBHOOK_URL` both change the day
the backend leaves ngrok. The passphrase is the one thing not in the repo and not recoverable. `restore`
refuses to clobber an existing file, so restoring onto a working machine cannot silently replace a
current `.env` with an older one — a failure that would surface much later as "everyone got logged out".

---

## Yandex MapKit Lite

The map is drawn natively by MapKit. It was `flutter_map` painting OpenStreetMap and then Mapbox tiles
with our own pins on top; Yandex's licence forbids pulling their tiles outside their SDK, so there was
no "swap the URL" version of this.

Billing is **monthly active users** (25 000 free), not per-request, so it does not move when somebody
drags the map. **Free tier or not, there is no hard cap: set a billing alert.** The Free licence's
conditions are ones we already meet — free to download, no turn-by-turn navigation, no monitoring or
dispatch. **If any of those three changes, the licence has to be revisited before the code is.**

**Lite, not the full package.** `yandex_maps_mapkit_lite` is the free-licence one: map, map objects,
camera, user location. The full package adds search, routing and panoramas — paid, and unused. Address
search and reverse geocoding **stay on Nominatim**.

**`domix_map.dart` is the entire boundary.** `DomixMap`, `DomixMapController` and `MapPin` are all the
screens see; nothing outside that file imports the SDK, which is why swapping the provider touched two
screens rather than twenty. **Keep it that way.**

### Traps, all of them silent

- **MapKit downloads nothing until `mapkit.onStart()` is called, and every symptom points elsewhere.**
  The surface comes up without it: GL context created, grey grid and Yandex logo drawn, camera moves,
  logcat shows a successfully `Chosen EGL config` — and not one error. It reads exactly like a rejected
  API key. The one signal that separates them is the **Yandex dashboard: zero requests.** A rejected key
  still counts as a request; an unstarted MapKit never makes one, so `0 из 1000 запросов` means the
  network layer was never started. Ping the tile host from the device
  (`adb shell ping core-renderer-tiles.maps.yandex.net`) to rule out the network first.
- **`onStart`/`onStop` live on the global `mapkit` singleton**, not on a map, so they cannot sit in one
  widget's `initState`/`dispose` — `location_picker_screen` can be pushed over `map_screen`, and the
  second map's `dispose` would stop the network layer under the first. `domix_map.dart` keeps a **count
  of mounted maps** plus the app's foreground state, and `_syncMapkitLifecycle()` reconciles the two;
  it no-ops when MapKit's state already matches, since `onStart` is not documented as idempotent. The
  foreground half is not a nicety — MapKit keeps sockets and caches warm while started. The singleton
  also means `mapkit_factory.dart` must be imported separately.
- **MapKit holds listeners by weak reference.** Camera, input and per-pin tap listeners are all fields
  on `_DomixMapState`, never locals. Anything only the native side points at is collected on the next GC
  and the callbacks silently stop — a map that works for ten seconds and then ignores the camera, with
  nothing in any log.
- **Pins are Flutter widgets rasterized off-screen.** `ViewProvider` takes a widget _builder_, lays it
  out against a `RenderRepaintBoundary` and hands MapKit the raster — which is why `ShopMarker` survived
  the migration unchanged. Two consequences: **no `InheritedWidget` reaches a pin** (no `Theme`, no
  `Provider` — a pin calling `Theme.of(context)` throws off-screen and nowhere else), and **a
  `GestureDetector` inside a pin does nothing** (taps arrive through `placemark.addTapListener`, which
  is why `MapPin.onTap` is a field and `ShopMarker.onTap` is always null on the map).
- **`MapPin.visualKey` does two jobs and must capture every visual difference.** It decides when the pin
  list is rebuilt _and_ it is MapKit's raster cache key, so forty identical pins are laid out once
  between them. A key that misses a difference caches the wrong bitmap; a key including the shop's name
  defeats the cache.

### Three things in `android/` exist only because of MapKit

Each failed in a way that named neither Yandex nor the real cause:

- **`compileSdk` is forced to 36 for every plugin subproject** (`android/build.gradle.kts`). Plugins pin
  their own and two disagree: MapKit compiles against 35, while `flutter_plugin_android_lifecycle` —
  which MapKit itself depends on — requires 36+. Two constraints on packages we do not own, so the fix
  has to be ours. **The placement is load-bearing twice over:** `afterEvaluate` rather than
  `plugins.withId` (withId fires as the plugin is _applied_, and the rest of its build file then sets 35
  straight back), and registered inside the _first_ `subprojects` block, because the later one calls
  `evaluationDependsOn(":app")` and an `afterEvaluate` added after that throws `Cannot run
Project.afterEvaluate(Action) when the project is already evaluated`.
- **`play-services-location`** is declared in `app/build.gradle.kts` — MapKit's location layer needs it
  and the plugin does not pull it in; without it the app compiles and dies at runtime.
- **Gradle's heap cap** in `android/gradle.properties` — see `frontend/CLAUDE.md`.

### Permissions MapKit merges in

Seven, none of which we ask for (we do not use `createUserLocationLayer`): `ACCESS_NETWORK_STATE`,
`ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_FINE_LOCATION`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`,
`FOREGROUND_SERVICE`. They show up on the Play listing. **Do not strip them blind with
`tools:node="remove"`** — a native SDK that checks for a permission it declared can fail at runtime, and
that only shows up on a device. `ACCESS_FINE_LOCATION` is the one Play makes you justify, and also the
one we will want the day the map grows a "where am I" button.

### What the move cost

**`minSdk` went 24 → 26** (MapKit's floor — the build fails outright below it), **building needs JDK
21+**, and **the map no longer runs on desktop or web** (`MapConfig.isSupportedPlatform` keeps the rest
of the app running there, with `MapUnavailablePanel` in the map's place).

**A Flutter upgrade will eventually break this.** The build already warns that plugins applying the
Kotlin Gradle Plugin — `yandex_maps_mapkit_lite` — will fail to build on future Flutter versions.
Nothing to do today; it is Yandex's to fix, but if a Flutter upgrade fails on Kotlin, this is why.

**Attribution is MapKit's job now.** The hand-rolled `_MapAttribution` pill is deleted, not moved: it
existed for OpenStreetMap's ODbL requirement, and MapKit draws Yandex's own logo and copyright as part
of the map surface. Adding ours back would credit the wrong party.

---

## Still open before release

**Nothing below is in progress.** The first group is ordered — the closed test runs on a calendar rather
than on effort, and the vault takes ten minutes and removes the worst outcome on the list.

### Do these first — they gate everything else

1. **Copy `secrets.vault.enc` somewhere off this laptop.** The script has been run once and verified
   (2026-08-17), so the passphrase works — but no copy exists anywhere else, leaving
   `~/domix-upload-key.jks`, the repo-root `.env` and `android/key.properties` on **one laptop and
   nowhere else**. Re-running `backup` does not close it, since it writes to the repo root. Write the
   passphrase on paper, off the laptop. `KEYS-AND-ACCOUNTS.txt` at the repo root has the full inventory.
2. **Start the closed test.** A personal Play developer account cannot apply for production access until
   it has run a closed test with **~12 testers opted in for 14 continuous days.** That is a calendar,
   not a task — start it and do everything else while it runs.
3. **Stand the production infrastructure up.** Decided 2026-08-21 and written down below; nothing has
   been bought yet. `env.prod.json` still says `https://REPLACE_ME` and `make release` refuses until it
   doesn't. Android 9+ blocks cleartext HTTP, so an `http://` address would fail every request silently
   in release. Nothing else on this page can be tested end to end without it.

### The production stack — decided, not yet bought

The domain is **`domix-api.uz`** (registered at eskiz.uz). It already reads as "api", so there is no
`api.` subdomain — the apex is the backend and there is exactly one subdomain:

| host               | serves                        | runs on       |
| ------------------ | ----------------------------- | ------------- |
| `domix-api.uz`     | the API and the two web pages | Hetzner VPS   |
| `img.domix-api.uz` | every product photo           | Cloudflare R2 |

**A plain VPS, not a container platform** (Hetzner CX22 / CAX11, ~€4–5/mo). Fly.io, Railway and Cloud
Run were considered and rejected on four counts, all of which are about _not migrating later_: a VPS is
the most portable thing there is (a move is rsync plus a dump restore, half a day, zero code changes);
no platform has a region near Tashkent; PostGIS is `apt install` on a VPS and a coin toss on managed
Postgres; and **every backend developer already knows how to SSH into Linux**, which matters the moment
somebody is hired. The cost is that sysadmin work — updates, certificates, backups, monitoring — is the
founder's. At one small machine that is the right trade.

**Latency to Tashkent is ~87 ms** to Hetzner's German datacentre, measured 2026-08-21 with `mtr` (the
international leg is one hop; everything before it is 3–5 ms, and the jitter in that trace was the
founder's own wifi, not the link). Fine for a marketplace, and mobile radio adds 30–80 ms on top
anyway. A local Uzbek host would give 5–15 ms and is a legitimate future move — **and it is not a
decision to agonise over, because moving between VPSes costs half a day and no code.**

**Nginx + certbot in front of Go.** Not a photo decision — it is how HTTPS and the domain work at all,
and Play rejects a cleartext app. Let's Encrypt is free and certbot renews on its own.

**Cloudflare R2 for photos, chosen for decoupling rather than because disk is broken.** On a VPS the
disk persists, so photos-on-disk would work; what R2 buys is that the one irreplaceable dataset (an
owner's uploads — the database can be restored from a dump, their photos cannot) stops being part of
the machine, stops being part of a host migration, and gets its backups for free. Its CDN is included
and switched on by default, which is worth nothing while the market is Tashkent and worth something the
day it is not. **The migration is cheap now and expensive later** — today it is one code path with no
data behind it; in a year it is also a file move plus rewriting every path in the database.

**DNS moves to Cloudflare**, because R2's custom-domain feature wants the zone there. Free: change the
nameservers at eskiz.uz to the two Cloudflare hands out. Both records then live in one panel — an `A`
for the apex pointing at the Hetzner IP, and R2 adds its own for `img.`.

Running cost: server ~€4–5, R2 free under 10 GB (then ~$0.015/GB), certificate free, domain owned.
**Roughly $6–8 a month.**

The order it gets done in: server → Cloudflare account → nameservers at eskiz → `A` record → Postgres
and nginx → certbot → deploy the binary → R2 bucket and `img.` → **upload `photos/` to the bucket** →
fill in `.env` (`IMAGE_BASE_URL` **and** the four `R2_*` keys, or the api will not start) → point
`env.prod.json` at `https://domix-api.uz` and ship the `.aab`.

**Still to verify before buying:** that an international Visa/Mastercard is accepted by both Hetzner and
Cloudflare. Uzbek Humo/UzCard do not work abroad; Hetzner also takes PayPal and bank transfer.

### The storage code is already written, and it is dormant until `.env` says otherwise

**All of this is built and tested (2026-08-21). Nothing below is a change still to make** — it is a
description of code that runs today on the disk path and switches to R2 when four variables are set at
step 9. Root §7 has the mechanics; what belongs here is what the deploy has to do about it.

1. **`imagestore.Storage`, two implementations, chosen once in `mustOpenPhotoStorage`.** `Disk` (laptop,
   every test, no network) and `R2` (production). The abstraction earns its place because **both are
   used every day** — an interface with one real implementation and one stub would not.
2. **Two files per photo** — a 1000px master and a 400px `_thumb`, the grid loading the thumbnail. That
   is ~99% of all image traffic and turns a 100-tile catalogue from ~15 MB into ~2.5 MB. Only the
   master's path is in the database; `ProductResponse` sends both urls ready-made.
3. **`IMAGE_BASE_URL`** is the host Go prepends. Unset, everything is served from this api's own
   `/static/products/`, which is what a laptop and the test suite want.

**Four things the deploy has to get right, and three of them are silent:**

- **The curated catalogue has to go into the bucket too**, `_thumb` files included. `photos/universal`
  and `photos/plumbing` are **gitignored**, so they exist only on the founder's laptop — the server will
  never have them. Every seeded row in every shop points at one, so a bucket with only `uploads/` in it
  is a market where the only visible photos are the ones owners took themselves:
  ```bash
  rclone copy photos/ r2:domix-photos/ --exclude 'uploads/**'   # or aws s3 sync --endpoint-url …
  ```
  Regenerate the thumbnails first if they are not there (root §7 has the `magick` loop).
- **R2 without `IMAGE_BASE_URL` refuses to boot**, deliberately: photos would be written to the bucket
  and served from a disk that does not have them — `/health` green, uploads answering 200, every tile
  blank. **Three R2 keys out of four also refuses to boot**, because falling back to the disk there
  gives a server that works until the next deploy takes the container's filesystem with it.
- **`img.domix-api.uz` must be R2's _public_ custom domain**, not the S3 endpoint. The S3 host wants a
  signature on every GET; the custom domain serves objects to anyone, which is what an `<img>` needs.
- **`PRODUCT_IMAGES_DIR` still matters on R2** only for `/static/products/`, which nothing will ask for
  once `IMAGE_BASE_URL` is set. The boot log prints which store and which url prefix are in use — that
  line is the fastest answer to "why are there no photos".

**Sweeping orphaned files is built too**, in the admin panel («Обзор» → «Файлы без товара», see the
`admin-panel` skill): uploads whose row went away with a deleted shop. It lists the files _first_ and the
database _second_, deletes only what is unreferenced **and older than an hour**, and treats a master's
path as claiming its `_thumb`. It is a button rather than a cron job — at this scale the number is zero
or single digits, and a scheduled process that deletes files is a thing to want a reason for.

### Play policy — a listing is rejected without each of these

- **A public account-deletion web page — built, blocked only on the domain.** `/delete-account` is
  served by the API (see the `admin-panel` skill). Two things remain: set **`SUPPORT_EMAIL`** to a
  mailbox somebody reads (unset prints `support@domix.uz`, which nobody owns, and a deletion page whose
  contact bounces is worse than none), and put the production URL in the Play Console.
- **App access instructions.** Login goes through a Telegram bot, so a reviewer with no Telegram account
  hits the login wall and rejects the submission as broken. Fill in the Console's **App access** section
  with a walkthrough and a screen recording — one of the most common rejections for phone-verified apps.
- **The Data Safety form.** Declare name, phone number, Telegram chat id, **approximate location** (a
  shop owner picks a point on a map), and now **in-app messages** (the support thread). It must match
  what the app does; a mismatch found later is a policy strike, not a correction.
- **Justify `ACCESS_FINE_LOCATION`** (see the MapKit permissions note above).
- Content rating questionnaire, target audience, and a privacy policy URL — all Console forms, all
  needing the domain.

### Code and build

- **Run `make apk` once the domain exists, with the emulator closed.** `make apk-test` covers most of it
  and is what has run on the Redmi; what it cannot cover is the production address. `make apk` is also
  the only way to confirm the upload key signs a real artifact end to end.
- **A Yandex MapKit API key in `env.prod.json`** — it says `REPLACE_ME`. The _development_ key is in
  `env.json` and working. Free plan, from Yandex's developer dashboard. Set a billing alert the day the
  key is created.
- **Keep testing on the device.** The map draws now, so pin rasterization, the teardrop's anchor, a tap
  opening the sheet, the camera listener surviving a GC, and the location picker's address keeping step
  are all finally reachable.
- **`shops.rating` is a stored column nothing writes** — root §6. Lighting the star needs a `reviews`
  table.
- **Pricing a hundred products costs ~500 taps**, and under the all-or-nothing rule an owner who stops at
  80 of 100 publishes **nothing**. It is a human problem, and the fix is a quick-entry list where the
  keyboard stays up and Next jumps to the next unpriced row. **Deferred deliberately** — do it when a
  real shop owner gives up halfway, not before.
- **`ListShops` has no `LIMIT` and no bounding box**, so opening the map fetches every shop. Irrelevant
  at 50–70; revisit around 1 000.
- **`shop_basket_index` is a plain view, not materialized**, and its `basket` CTE is referenced twice — a
  materialization barrier, so postgres cannot push the category predicate down and every query touching
  it sequentially scans every template product row. `GET /api/home` pays that five times. Measured: ~3 ms
  per home request at 50 shops, 36 ms at 1 000, 175 ms at 5 000. **The axis that hurts is shop count, not
  user count.** Past ~1 000 shops the fix is a materialized view refreshed on price change or a cached
  home payload — **not** a bigger connection pool.
- **Delete `DevicePreview`** — see `frontend/CLAUDE.md`, and read the note there before removing it a
  third time.

### Infrastructure and operations

- **Database backups.** There is no `pg_dump` on any schedule. Every shop's catalogue is hand-typed by
  its owner and exists in exactly one place; losing it does not lose a demo, it loses work real people
  did. **This ranks above every polish item on this list.**
- **Nominatim** is still the free public instance: ~1 req/sec shared across every user, and no production
  traffic allowed. With 50 owners registering addresses at once the symptom is 429s and then a temporary
  IP block, which reads to them as "address search is broken" with nothing in the server's logs. Cheap
  mitigation first — cache repeated lookups and send a real contact `User-Agent`, which their policy
  requires — self-hosting later. MapKit Lite has no search to move it to.
- **No error reporting.** When the app breaks on an owner's phone, nobody finds out. Structured server
  logs plus a crash reporter would turn "it doesn't work" into a stack trace. (The support inbox is now
  the closest thing there is — but it needs the user to write in.)
- **Nothing exposes `pool.Stat().EmptyAcquireCount()`** — the count of requests that had to wait for a
  connection, and the only evidence that would justify changing `DB_MAX_CONNS`. Ten lines behind a
  token-protected `/metrics`.
- **The glibc collation mismatch on the local database.** `domix_db` was created under glibc 2.43 and the
  OS now provides 2.44, so `CREATE DATABASE` from `template1` fails outright. The repair is
  `REINDEX DATABASE domix_db;` **and then** `ALTER DATABASE domix_db REFRESH COLLATION VERSION;` — in
  that order. Refreshing alone only silences the warning while leaving text indexes possibly sorted by
  the old rules.
- **CORS is still `Access-Control-Allow-Origin: *`, and that is still fine.** CORS is a browser rule, and
  the admin panel is served from the API's **own origin**, so its requests are not cross-origin and never
  consult the header. What the wildcard permits is another site's javascript calling this API — and every
  admin route requires an `Authorization` header, which a browser will not attach cross-origin on its
  own. **The day something authenticates with a cookie, this becomes urgent**; while it is bearer tokens
  in `localStorage`, it is not.
- **A slow request _body_ is still unbounded in time, on the two public POSTs.** `ReadHeaderTimeout`
  (10s) and `IdleTimeout` (120s) are set on the server and close the slowloris hole — a connection that
  dribbles its _headers_ — but `ReadTimeout`/`WriteTimeout` are deliberately absent, because they budget
  the whole request and would cut off a 6 MiB photo upload on 3G (the comment above `srv` in
  `cmd/api/main.go` says so at length; **do not add them**). What that leaves: a caller can send valid
  headers, pass the guard, and then feed the body one byte at a time forever. `http.MaxBytesReader`
  bounds the bytes (64 KiB generally, 6 MiB on a photo) and nothing bounds the time.
  **The photo endpoint barely matters** — it sits behind `RequireAuth` and a per-account limiter, so it
  costs a real Telegram-verified account. The real exposure is `POST /api/auth/init` and
  `POST /api/account-deletion/init`: public, body-carrying, and the login limiter counts _requests_,
  which an unfinished one never becomes. **Fix before going live on the domain**, per-handler rather than
  globally: `http.NewResponseController(w).SetReadDeadline(time.Now().Add(…))` at the top of those two.
- **No refresh token.** The user-existence check in `RequireAuth` covers deletion, but a _stolen_ token
  belonging to a live account works until it expires. Revoking one without deleting the account needs a
  `token_version` column bumped on logout.
- **`TRUST_PROXY`**: only turn it on once something in front _always_ rewrites `X-Forwarded-For`, since
  both ways of getting it wrong fail silently.
