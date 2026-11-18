# Build commands for the Domix app.

.PHONY: help setup dev dev-skia desktop emulator gradle-stop guard-jdk analyze test check guard-env guard-prod apk-test apk release guard-mac ipa clean

help:
	@echo "make setup     - first time: write a starter env.json and fetch packages"
	@echo "make emulator  - boot the domix Android emulator (leave it running)"
	@echo "make dev       - run on an Android device/emulator against your local backend"
	@echo "make dev-skia  - same, but on the old renderer. try this if the emulator stutters."
	@echo "make desktop   - run on Linux instead. FASTER, but the map does not exist there."
	@echo "make check     - analyze + test, what CI should run"
	@echo "make gradle-stop - kill the Gradle daemon and get its RAM back"
	@echo "make apk-test  - RELEASE build against your own backend. what to sideload today."
	@echo "make apk       - production APK. needs a real domain in env.prod.json first."
	@echo "make release   - production app bundle (.aab), the file Google Play wants"
	@echo "make ipa       - production iOS archive (.ipa), the file App Store Connect wants. macOS only"

# Writes the starter env.json inline rather than copying a committed template. There is no
# env.example.json: a two-key file is not worth a fourth copy of the same two keys, and a template
# nobody edits drifts out of date silently. env.prod.json is the committed reference for the shape.
setup:
	@test -f env.json || printf '%s\n' \
		'{' \
		'  "API_BASE_URL": "https://jeep-prepay-penholder.ngrok-free.dev/api/auth",' \
		'  "MAPKIT_API_KEY": ""' \
		'}' > env.json
	flutter pub get
	@echo "env.json ready - check API_BASE_URL and fill in MAPKIT_API_KEY."

emulator:
	flutter emulators --launch domix

# See tool/check-jdk.sh - it resolves the JDK the way Flutter does, which is not the way the shell
# does. On this machine `java` on PATH is 17 while flutter's --jdk-dir is 21.
guard-jdk:
	@./tool/check-jdk.sh

# `dev` is pinned to Android on purpose. Left to itself `flutter run` picks whatever single device
# it can see, which on this machine is the Linux desktop - where MapKit does not exist and every map
# screen is a placeholder. Silently running the one build that cannot show the feature you are
# working on is worse than refusing.
#
# `-d` matches a device's id or its name, never its target platform - so `-d android` matched nothing
# even with the emulator running, and the error listed "android-x64" right there in the platform
# column, which reads like the thing that was asked for. The emulator's real id is `emulator-5554`,
# and it is not stable enough to hardcode (a second emulator gets 5556). So resolve it at run time.
ANDROID_DEVICE = flutter devices --machine 2>/dev/null | jq -r 'map(select(.targetPlatform | startswith("android"))) | .[0].id // empty'

dev: guard-jdk
	@id=$$($(ANDROID_DEVICE)); \
	test -n "$$id" || { \
		echo "ERROR: no Android device is connected."; \
		echo "       Run 'make emulator' and wait for the home screen, then try again."; \
		exit 1; }; \
	echo "flutter run -d $$id --dart-define-from-file=env.json"; \
	flutter run -d "$$id" --dart-define-from-file=env.json

# Same as `dev` but on Skia, Flutter's previous renderer, instead of Impeller.
#
# Impeller is the default and it is what ships, so this is a diagnostic and not a workflow: it exists
# because Impeller talks to the GPU through the emulator's translation layer, and that layer is where
# emulator stutter usually comes from rather than from anything in our code. If scrolling is smooth
# here and rough under `dev`, the app is fine and the emulator is the bottleneck.
#
# **Do not judge a layout's performance from either.** A debug build interprets Dart rather than
# running compiled code; the honest measurement is `make apk` on a real phone.
dev-skia: guard-jdk
	@id=$$($(ANDROID_DEVICE)); \
	test -n "$$id" || { \
		echo "ERROR: no Android device is connected."; \
		echo "       Run 'make emulator' and wait for the home screen, then try again."; \
		exit 1; }; \
	flutter run -d "$$id" --dart-define-from-file=env.json --no-enable-impeller

# The desktop build is still useful and still supported - it is much faster to iterate on the home
# screen, the forms and the profile there. It just cannot show a map.
desktop:
	flutter run -d linux --dart-define-from-file=env.json

# The Gradle daemon stays resident between builds holding ~2 GB, which is a lot on a 7.4 GB laptop.
# It is worth keeping while iterating and worth killing when switching to something else.
gradle-stop:
	cd android && ./gradlew --stop

analyze:
	flutter analyze

test:
	flutter test

check: analyze test

# Refuses to build a release that would ship a placeholder.
#
# Without this the failure is silent and late: the app installs, opens, and every screen sits on a
# spinner because it is calling https://REPLACE_ME. Android also blocks cleartext HTTP from API 28
# onwards, and iOS's App Transport Security likewise, so an http:// address fails the same silent
# way - hence the second check.
guard-env:
	@test -f env.prod.json || { echo "ERROR: env.prod.json is missing"; exit 1; }
	@grep -q 'REPLACE_ME' env.prod.json && { \
		echo "ERROR: env.prod.json still contains REPLACE_ME - fill in the real values first."; \
		exit 1; } || true
	@grep -q '"API_BASE_URL": "http://' env.prod.json && { \
		echo "ERROR: API_BASE_URL is http:// - Android blocks cleartext traffic, every request will"; \
		echo "       fail silently in a release build. Use https://."; \
		exit 1; } || true
	@grep -q '"MAPKIT_API_KEY": ""' env.prod.json && { \
		echo "ERROR: MAPKIT_API_KEY is empty - the map screens would ship showing a placeholder"; \
		echo "       panel instead of a map. Get a key from Yandex's developer dashboard."; \
		exit 1; } || true

guard-prod: guard-env
	@test -f android/key.properties || { \
		echo "ERROR: android/key.properties is missing, so this would be signed with the debug key"; \
		echo "       and Google Play would reject it. See android/key.properties.example."; \
		exit 1; }

# A release build pointed at env.json instead of env.prod.json.
#
# This exists because `apk` cannot run until there is a production domain, and the thing most worth
# discovering early has nothing to do with the domain. A release build is a *different program* from
# a debug one: Dart is compiled ahead of time instead of interpreted, and R8 deletes and renames code
# it believes nothing calls. MapKit's native layer looks its Java classes up by name over JNI, which
# R8 cannot see - so a wrong `proguard-rules.pro` shows up as a blank map in release and in nothing
# else. Waiting for a domain to find that out means finding it out after upload.
#
# What this does NOT test is the production address, which is the one thing env.prod.json carries
# that env.json does not. Run `apk` too, once the domain exists.
apk-test: guard-jdk
	flutter build apk --release --dart-define-from-file=env.json
	@echo ""
	@echo "Install on a phone plugged in over USB:"
	@echo "  adb install -r build/app/outputs/flutter-apk/app-release.apk"

apk: guard-jdk guard-prod
	flutter build apk --release --dart-define-from-file=env.prod.json

release: guard-jdk guard-prod check
	flutter build appbundle --release --dart-define-from-file=env.prod.json
	@echo ""
	@echo "Upload: build/app/outputs/bundle/release/app-release.aab"

guard-mac:
	@test "$$(uname)" = Darwin || { echo "ERROR: an iOS build needs macOS and Xcode."; exit 1; }

# signing is xcode's automatic signing with the team picked once in Runner.xcworkspace, so nothing
# for it lives in this repo, unlike android/key.properties
ipa: guard-mac guard-env check
	flutter build ipa --release --dart-define-from-file=env.prod.json
	@echo ""
	@echo "Upload: build/ios/ipa/*.ipa, with Transporter or Xcode's Organizer"

clean:
	flutter clean
	flutter pub get
