# Android build, signing and device testing

Read when touching `frontend/android/`, the launcher icon, R8 rules, `env*.json`, or sideloading to the
test phone. UI-side trades (no text scaling, portrait lock, the floating nav bar's inset) are in the
`frontend` skill.

---

## Android config

All of it was `flutter create` placeholder:

|                              | was                            | is                                        |
| ---------------------------- | ------------------------------ | ----------------------------------------- |
| `applicationId`, `namespace` | `com.example.frontend`         | `app.domix`                               |
| `android:label`              | `frontend`                     | `Domix`                                   |
| launcher icon                | Flutter logo, no adaptive icon | Domix pin, legacy + adaptive + monochrome |
| release signing              | the debug key                  | `android/key.properties`, gitignored      |

**`applicationId` is permanent from the first upload** — it is the listing's primary key; changing it later
means a different app with zero installs and reviews. Play rejects `com.example.*` and requires two
dot-separated segments. `app.domix` carries no country and no platform. `MainActivity.kt` lives in
`kotlin/app/domix/`. **Settled — do not change it.**

**Domix is a mobile app, not a web platform.** Any web page the project serves exists because Play requires
a URL or because people need somewhere to read about the app, never as the product.

### The launcher icon

Android 8 masks two layers itself, so the launcher decides whether Domix is a circle, squircle or rounded
square; a single flat PNG gets pillar-boxed inside a white rounded square.
`mipmap-anydpi-v26/ic_launcher.xml` declares a flat `@color/ic_launcher_background` (`#F26B21`, sampled from
the artwork, close but not equal to `AppColors.primaryOrange`), the white pin as foreground, and the same
pin as the Android 13 `<monochrome>` layer.

**The foreground's size is load-bearing.** The layer is 108dp but only the central **66dp** survives every
mask, and launchers pan the rest during animations. The pin is drawn at 560/1024 of the canvas — furthest
point 280px from centre against the 313px the safe circle allows. **Regenerating from new artwork means
redoing that arithmetic, not just resizing.** The source PNG is not in the repo and not on this laptop; it
has to be re-exported before the icon can be regenerated.

### Release signing

The release build reads the upload key from `android/key.properties` (see `key.properties.example`) and
**falls back to debug signing with a warning when it is absent or its `storeFile` does not resolve**, so a
checkout without the key still runs. That cannot ship by accident — Play refuses a debug-signed artifact —
but it does mean **a wrong `storeFile` path is a silent downgrade to the debug key**.

```bash
keytool -genkey -v -keystore ~/Main/domix-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias domix
```

`key.properties` holds four lines: `storeFile`, `storePassword`, `keyPassword`, `keyAlias`. Play verifies
every update against the first upload's signature, so **a lost `.jks` cannot be rotated or regenerated** —
the only path is a new listing.

### R8 and `proguard-rules.pro`

Flutter's Gradle plugin picks the file up by filename. R8 only runs for release: it deletes code nothing
appears to call and renames the rest, deciding "nothing calls this" by reading the code — so anything looked
up **by name at run time** is invisible to it, and MapKit's native layer does exactly that over JNI. The
rules keep `com.yandex.**` whole, plus `androidx.security.crypto.**` (flutter_secure_storage builds its
crypto reflectively — stripped, the release build silently cannot read its own stored JWT and every user
appears logged out).

**The symptom of a wrong rule is a debug build that works forever and a release build with a blank map or an
empty session, discovered after upload.** `make apk-test` is what finds it before then.

---

## `env.json` vs `env.prod.json`

| file            | committed?     | holds                                                       |
| --------------- | -------------- | ----------------------------------------------------------- |
| `env.json`      | no, gitignored | the developer's own backend (an ngrok tunnel)               |
| `env.prod.json` | **yes**        | the production API address and the Yandex MapKit public key |

**Nothing in a `--dart-define` can be secret** — the values become plain constants in the binary and come
out of a shipped APK with a hex editor. So the file can only hold public facts, and keeping it in git is
what makes a release reproducible.

`make release` runs `guard-prod` and refuses on a placeholder `REPLACE_ME`, on an `http://` API address, or
with `android/key.properties` missing. All three fail *silently* otherwise — every screen sits on a spinner,
or Play rejects the upload.

State: `MAPKIT_API_KEY` is filled in and working. `API_BASE_URL` is still `https://REPLACE_ME`.

---

## Testing on a real Android phone

Reference device: **Redmi Note 9S** (MIUI). Two setups, each done once.

**On this Arch laptop** — `adb` cannot talk to USB without udev rules and group membership:

```bash
sudo pacman -S android-udev
sudo usermod -aG adbusers ayzrixsiev
```

**Then log out and back in.** A login session captures its group list at start and cannot pick up a new one,
so every process keeps running without the group until the session is replaced. The tell is `id -nG` and
`groups` disagreeing. `usermod` prints nothing on success — check the group file, not the exit code.

**On the phone — MIUI needs more than stock Android.** Developer mode: Settings → About phone → tap **MIUI
version** 7×. Then in Developer options:

| toggle                                                | needed for                                                                              |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Отладка по USB**                                    | the standard one                                                                        |
| **Установка через USB**                               | MIUI-only, blocks `adb install`. Needs a signed-in Mi account and internet — verifies online |
| Default USB configuration → **Передача файлов (MTP)** | "Только зарядка" blocks adb on several MIUI builds                                      |
| Отладка по USB (настройки безопасности)               | **not** needed for installing — leave it off                                             |

A correct phone reads `device` in `adb devices -l` — not `unauthorized` (fingerprint prompt not accepted)
and not `no permissions` (the group step did not take).

**Install with `make apk-test`.** It calls the ngrok tunnel because `API_BASE_URL` is compiled in, so
**ngrok and the api must both be up or every screen is empty**. The phone does not need the laptop's wifi.
Once installed the app is standalone — a change means rebuild and reinstall.

**Two bugs have been found that can only appear here**, which is the argument for doing it early: Android 11
package visibility breaking every `url_launcher` call, and R8. Neither reproduces on desktop or emulator.
