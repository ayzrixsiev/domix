# Android build, signing and device testing

Read when touching `frontend/android/`, the launcher icon, R8 rules, `env*.json`, or sideloading to the Redmi.

---

## Accessibility and orientation trades

**The app ignores the phone's font-size setting** — `main.dart` wraps everything in
`MediaQuery.withNoTextScaling`. Deliberate: fixed card heights (`ProductTile.height` 208,
`VipShopsCarousel.cardHeight` 232) leave scaled text nowhere to go. On a 360dp phone the VIP card
overflows at scale **1.15** (one notch above default), product tiles at 1.5. The honest fix is cards
that size to their content; **if that gets built, delete the wrapper rather than raising the
constants.** Accepted knowingly.

> **Measure text overflow with a real font loaded.** `flutter test` draws every glyph as a full em
> square, so Cyrillic comes out ~2× its real width and the harness invents overflows. Load one first:
> `FontLoader('Roboto')..addFont(...)` over any system TTF with Cyrillic.

**A custom `bottomNavigationBar` must inset itself.** Flutter's own adds `MediaQuery.padding.bottom`;
hand-rolled `FloatingBottomNavBar` did not, so its lowest 48px sat behind the system nav buttons. It
now adds `MediaQuery.viewPaddingOf(context).bottom` — **viewPadding, not padding**: `padding`
collapses to zero while the keyboard is open, dropping the bar into the system buttons for as long as
anyone types.

**Portrait is locked** in `main()` — every screen is a vertical feed, a map or a form.

---

## Android config

All of it was `flutter create` placeholder:

|                              | was                            | is                                        |
| ---------------------------- | ------------------------------ | ----------------------------------------- |
| `applicationId`, `namespace` | `com.example.frontend`         | `app.domix`                               |
| `android:label`              | `frontend`                     | `Domix`                                   |
| launcher icon                | Flutter logo, no adaptive icon | Domix pin, legacy + adaptive + monochrome |
| release signing              | the debug key                  | `android/key.properties`, gitignored      |

**`applicationId` is permanent from the first upload** — it is the listing's primary key; changing it
later means a different app with zero installs and reviews. Play rejects `com.example.*` and requires
two dot-separated segments. `app.domix` is the founder's choice: no country, no platform. Not
conventional reverse-DNS, and that is fine. **Domix is a mobile app, not a web platform** — any web
page the project serves (privacy policy, account deletion, a marketing page) exists because Play
requires a URL or because people need somewhere to read about the app, never as the product.
`MainActivity.kt` lives in `kotlin/app/domix/`, `userAgentPackageName` on both maps matches. **Settled — do not change it.**

### The launcher icon

Android 8 masks two layers itself, so the launcher decides whether Domix is a circle, squircle or
rounded square; a single flat PNG gets pillar-boxed inside a white rounded square.
`mipmap-anydpi-v26/ic_launcher.xml` declares a flat `@color/ic_launcher_background` (`#F26B21`,
sampled from the artwork, close but not equal to `AppColors.primaryOrange`), the white pin as
foreground, and the same pin as the Android 13 `<monochrome>` layer.

**The foreground's size is load-bearing.** The layer is 108dp but only the central **66dp** survives
every mask, and launchers pan the rest during animations. The pin is drawn at 560/1024 of the canvas
— furthest point 280px from centre against the 313px the safe circle allows. **Regenerating from new
artwork means redoing that arithmetic, not just resizing.** Source is `domix_icon.png` at the repo
root — untracked, referenced by nothing.

### Release signing

The release build reads the upload key from `android/key.properties` (see `key.properties.example`)
and **falls back to debug signing with a warning when it is absent**, so a checkout without the key
still runs. That cannot ship by accident — Play refuses a debug-signed artifact.

```bash
keytool -genkey -v -keystore ~/domix-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias domix
```

`key.properties` holds four lines: `storeFile`, `storePassword`, `keyPassword`, `keyAlias`. The
`.jks` is a keystore holding the private signing key; Play verifies every update against the first
upload's signature. **A lost `.jks` cannot be rotated or regenerated** — the only path is a new
listing.

### R8 and `proguard-rules.pro`

Flutter's Gradle plugin picks the file up by filename. R8 only runs for release: it deletes code
nothing appears to call and renames the rest, deciding "nothing calls this" by reading the code — so
anything looked up **by name at run time** is invisible to it, and MapKit's native layer does exactly
that over JNI. The rules keep `com.yandex.**` whole, plus `androidx.security.crypto.**`
(flutter_secure_storage builds its crypto reflectively — stripped, the release build silently cannot
read its own stored JWT and every user appears logged out).

**The symptom of a wrong rule is a debug build that works forever and a release build with a blank
map or an empty session, discovered after upload.** `make apk-test` is what finds it before then.

---

## Build files: `env.json` vs `env.prod.json`

| file            | committed?     | holds                                                       |
| --------------- | -------------- | ----------------------------------------------------------- |
| `env.json`      | no, gitignored | the developer's own backend (an ngrok tunnel)               |
| `env.prod.json` | **yes**        | the production API address and the Yandex MapKit public key |

**Nothing in a `--dart-define` can be secret** — the values become plain constants in the binary and
come out of a shipped APK with a hex editor. So the file can only hold public facts, and keeping it
in git is what makes a release reproducible.

`make release` runs `guard-prod` and refuses on a placeholder `REPLACE_ME`, on an `http://` API
address, or with `android/key.properties` missing. All three fail _silently_ otherwise — every screen
sits on a spinner, or Play rejects the upload.

State: `MAPKIT_API_KEY` is filled in and working. `API_BASE_URL` is still `https://REPLACE_ME`.

---

## Testing on a real Android phone

Reference device: **Redmi Note 9S** (`curtana`, MIUI). Two setups, each done once.

**On this Arch laptop** — `adb` cannot talk to USB without udev rules and group membership:

```bash
sudo pacman -S android-udev
sudo usermod -aG adbusers ayzrixsiev
```

**Then log out and back in.** A login session captures its group list at start and cannot pick up a
new one, so every process keeps running without `adbusers` until the session is replaced. The tell is
`id -nG` and `groups` disagreeing. `usermod` prints nothing on success — check the group file, not
the exit code.

**On the phone — MIUI needs more than stock Android.** Developer mode: Settings → About phone → tap
**MIUI version** 7×. Then in Developer options:

| toggle                                                | needed for                                                                              |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Отладка по USB**                                    | the standard one                                                                        |
| **Установка через USB**                               | MIUI-only, blocks `adb install`. Needs a signed-in Mi account and internet — verifies online |
| Default USB configuration → **Передача файлов (MTP)** | "Только зарядка" blocks adb on several MIUI builds                                      |
| Отладка по USB (настройки безопасности)               | **not** needed for installing — leave it off                                             |

A correct phone reads `device` in `adb devices -l` — not `unauthorized` (fingerprint prompt not
accepted) and not `no permissions` (group step did not take).

**Install `make apk-test`.** It calls the ngrok tunnel because `API_BASE_URL` is compiled in, so
**ngrok and `go run ./cmd/api` must both be up or every screen is empty**. The phone does not need
the laptop's wifi. Once installed the app is standalone — a change means rebuild and reinstall.

**Two bugs have been found that can only appear here**, which is the argument for doing it early:
Android 11 package visibility breaking every `url_launcher` call (root §8), and R8. Neither
reproduces on desktop or emulator.

> The keystore backup itself (`scripts/secrets.sh`, the vault) lives in `SKILL.md`.
