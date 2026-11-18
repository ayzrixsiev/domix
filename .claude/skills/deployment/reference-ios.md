# The App Store build

Read on the Mac, before anything else. **The Mac is borrowed for a short time**, so everything that
did not need one was done on Linux beforehand; the session there is the checklist below and nothing
else.

**There is no iOS UI code.** `lib/` is the same app; `frontend/ios/` is only the native shell.

---

## Already done in the repo (2026-11-16, on Linux)

| | value | why |
| --- | --- | --- |
| bundle id | `app.domix` | the same as Android's `applicationId`; **permanent from the first upload**, like it |
| display name | `Domix` | |
| devices | **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`) | an iPad build needs its own screenshots and its own review pass, for an app locked to portrait phone cards |
| minimum iOS | 15.0, in `Podfile` and the xcode project | `yandex_maps_mapkit_lite` declares 15 |
| orientation | portrait | matches `main.dart` |
| languages | `ru` (development region), `uz` | the app's `supportedLocales`; without `CFBundleLocalizations` iOS draws its own dialogs in English |
| permission texts | location, camera, photo library, in Russian | Apple rejects a missing or vague one. **The location text says the coordinate stays on the phone, which is what the privacy labels answer** |
| export compliance | `ITSAppUsesNonExemptEncryption = false` | the app uses HTTPS only; saves the question on every upload |
| icon | one 1024 px, no alpha, cut from `domix_icon.png` | iOS rounds the corners itself; App Store Connect refuses an icon with transparency |
| plugins | CocoaPods, Swift Package Manager **off** in `pubspec.yaml` | Yandex's `Package.swift` pulls its SDK by a registry id nothing resolves; its podspec builds |
| `make ipa` | `guard-env` + `check` + `flutter build ipa` with `env.prod.json` | refuses anywhere but macOS |

Not needed, checked: no `LSApplicationQueriesSchemes` — `url_launcher_ios`'s `launchUrl` calls
`UIApplication.open` and reports failure itself, so the Telegram link, `tel:` and the
`yandexmaps://` → Google fallback all work undeclared (only `canLaunchUrl` needs the list, and the
app never relies on it). No `AppDelegate` code for MapKit — `initMapkit` runs from Dart. The
`retrieveLostData` call is Android-only on purpose: iOS does not kill the app under the camera.

---

## Before the Mac — the founder

1. **Apple Developer Program, $99/year, as an individual** (the Play account is a private individual
   too). Approval takes days, so it is first.
2. **The Yandex MapKit key.** The key in `env.prod.json` is not tied to a platform unless it was
   restricted in the cabinet. If it has an application restriction, add the iOS bundle id `app.domix`
   to it; otherwise nothing to do.
3. Six or more iPhone screenshots at 6.9" (1320×2868 or 1290×2796). The simulator on the Mac can take
   them, so this can also wait.

---

## On the Mac, in order

1. **Install**: Xcode from the App Store (opened once, licence accepted, an iOS simulator runtime
   downloaded), Homebrew, then `brew install cocoapods` and Flutter 3.44.x (the version this repo
   builds with — `flutter --version` here).
2. **Clone** the repo, `cd frontend`, `flutter pub get`, `cd ios && pod install && cd ..`.
   `pod install` fetches `YandexMapsMobile` from the CocoaPods CDN — a large download.
3. **Run it** on the simulator: `flutter run --dart-define-from-file=env.prod.json`. Check the map
   draws tiles, «Рядом со мной» asks for location in Russian, and sign-in via Telegram opens the link.
   **The simulator has no Telegram and no camera**: the phone-number route with the review account
   (`998901110000` and the real code from the founder's notes, not the docs' `424242` example)
   proves sign-in there. A real iPhone over USB is better if one is around.
4. **Signing**: `open ios/Runner.xcworkspace` (the workspace, never the `.xcodeproj`), Runner target →
   Signing & Capabilities → tick automatic signing, pick the team. This writes `DEVELOPMENT_TEAM` into
   `project.pbxproj`; **commit that line**, so the next build on another Mac only needs the account
   signed in.
5. **App Store Connect** (appstoreconnect.apple.com) → My Apps → + → New App: iOS, name `Domix`,
   primary language Russian, bundle id `app.domix`, SKU `domix`.
6. **Build**: `make ipa` → `build/ios/ipa/*.ipa`. Upload it with Apple's Transporter app (sign in, drag
   the file in). The build appears in App Store Connect after ~10–30 min of processing.
7. **TestFlight** first: add the testers' Apple IDs as internal testers — no 14-day rule like Play.

Commit and push from the Mac before giving it back: the `pbxproj` team line and `Podfile.lock`.
`Pods/` is ignored and stays local.

---

## The listing — any computer, in App Store Connect

- **Privacy Policy URL** `https://domix-app.uz/privacy`; support URL `https://domix-app.uz`.
- **App Privacy** (Apple's version of Data Safety): the same answers as `docs-privacy.md` — name,
  phone number, photos, user content (the store, waybills), all linked to the user, none for tracking.
  **Location: not collected**, for the reason the Play form gives.
- **Sign-in information** for review: `998901110000`, the same code the Play listing gives, and the line «Профиль → Войти →
  … → Войти по номеру телефона». **The api must have `PLAY_REVIEW_PHONE` armed**, as for Play.
- **Account deletion** is required in-app (guideline 5.1.1(v)); the app has it, and
  `https://domix-app.uz/delete-account` exists.
- Age rating questionnaire, category (Shopping), price Free, availability: Uzbekistan (or all).
- **Sign in with Apple is not required**: guideline 4.8 applies to third-party *social* logins, and
  Telegram-number and phone-code sign-in is the app's own account system. If a reviewer disagrees,
  the answer is the guideline text, not new code.
