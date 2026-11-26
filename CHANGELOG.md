## 0.1.0-beta.1

- First beta: Android and iOS releases and patches work end to end on real phones.
- README: how to try releases and patches on the iOS Simulator and Android emulator (`otadart release ios --simulator`).
- README: what OTADart does, measured on a real iPhone 17 Pro and Samsung Galaxy A15.

## 0.1.0-dev.7

- README: patches update images, fonts and other assets — not just code; patch sizes and app speed measured on a real iPhone 17 Pro and Samsung Galaxy A15.

## 0.1.0-dev.6

- Web support: the package now compiles for Flutter web (JavaScript and WebAssembly). On the web it detects a newer deployed build from `version.json`; `availableUpdate()` reports its `version`, and `restart()` reloads the page onto it. Same API on every platform.
- New `canRestart` and `restart()` (on mobile and desktop a patch still applies on the next launch).

## 0.1.0-dev.5

- Follow another track at runtime: `update(track: UpdateTrack.beta)`, `availableUpdate(track: 'qa')`, or set `preferredTrack` once.
- Update checks report the running patch and failed launches, so the console shows installs and patch adoption, and a broken patch is rolled back automatically for everyone. No personal data is sent.

## 0.1.0-dev.4

- Android: finds the OTADart engine automatically (opens libflutter.so), so patches download and apply in release builds.
- `info().releaseVersion` and `label` show the release version with every engine build.

## 0.1.0-dev.3

- Code style: all recommended Dart lints pass.

## 0.1.0-dev.2

- `info()`: release version, current and next patch number, track, platform, health — in one call.
- `currentPatch()` and `nextPatch()`.
- `availableUpdate()`: check what's offered without downloading.
- `update()`: download and stage (same as `checkForUpdate()`).
- `OtaDart.tryInitialize()` and `OtaDart.isSupported()`: safe in `flutter run` and plain builds.
- `track`, `appId`, `releaseVersion` getters.

## 0.1.0-dev.1

- First preview: connect with `OtaDart.initialize`, check for patches, progress events, automatic checks and launch health confirmation.
