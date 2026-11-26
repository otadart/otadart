<p><img src="https://otadart.dev/brand/logo-96.png" width="48" height="48" alt="OTADart"></p>

# otadart

Connect your Flutter app to [OTADart](https://otadart.dev) — over-the-air Dart updates for Android and iOS.

Your app checks for a signed patch, downloads it in the background, and applies it the next time it opens. If a patched launch fails, it falls back automatically.

> **Patches update your assets too — not just code.** Most code-push tools send code only. OTADart also sends changed and new images, fonts and other files in the same patch as your Dart code. Tested on a real iPhone 17 Pro and Samsung Galaxy A15: a patch that added a new photo showed it on both phones.

## Why OTADart

| | |
|---|---|
| **Images, fonts & other assets** | ✅ Sent in the patch |
| **Every patch signed & verified** | ✅ Always, on every plan |
| **Free plan** | ✅ 10,000 patch activations a month |
| **Test before your users** | ✅ Releases and patches run on the iOS Simulator and Android emulator too |
| Automatic rollback | On the phone, plus on the server when a patch fails on too many devices |
| App speed after a patch | Same as the store build (Android 104 ms vs 108 ms · iPhone 66 ms vs 79 ms) |

Measured on a real iPhone 17 Pro and Samsung Galaxy A15 (November 2026). Details: [otadart.dev/docs/performance](https://otadart.dev/#/docs/performance).

## Self-hosting

Run the OTADart update service on your own server for free. [Self-hosting setup guide](https://otadart.dev/docs/self-hosting)

## Test on a simulator or emulator

Try a release and its patches before they reach real users:

```sh
# Android emulator
otadart release android
otadart preview android --device-id emulator-5554
otadart patch android

# iOS Simulator (testing only — not for the App Store)
otadart release ios --simulator
otadart preview ios
otadart patch ios --simulator
```

Close and reopen the app to see the patch: it is applied on the next launch.

## Install

```sh
flutter pub add otadart@0.1.0-beta.4
```

`otadart init` adds it for you. Install the CLI with:

```sh
curl -fsSL https://otadart.dev/install.sh | bash
```

## Quick start

One line after `runApp` — `otadart init` adds it for you:

```dart
import 'package:otadart/otadart.dart';

void main() {
  runApp(const MyApp());
  OtaDart.start(appId: 'YOUR-APP-ID'); // from otadart.yaml
}
```

`OtaDart.start` does the recommended setup:

- checks for a patch at launch and downloads it in the background (it applies on the next launch),
- checks again every 6 hours while the app runs,
- confirms the launch after 10 seconds — if a patch crashes the app before that, the next launch rolls back to the previous code.

It returns `null` in `flutter run` and in builds not made with `otadart release`, so the same code is safe everywhere.

## Automatic checks: on, off, how often

```dart
OtaDart.start(
  appId: 'YOUR-APP-ID',
  checkOnLaunch: true,                         // check when the app starts (default)
  firstCheckAfter: const Duration(seconds: 5), // wait before the first check (default: none)
  autoCheck: true,                             // keep checking while the app runs (default)
  checkEvery: const Duration(hours: 1),        // 15 minutes – 7 days (default 6 hours)
  healthyAfter: const Duration(seconds: 10),   // null = call markCurrentBootHealthy() yourself
);

OtaDart.start(appId: 'YOUR-APP-ID', autoCheck: false);                     // only at launch
OtaDart.start(appId: 'YOUR-APP-ID', checkOnLaunch: false, autoCheck: false); // only when you call update()
```

Turn checks on or off later, e.g. from a settings screen:

```dart
final updates = await OtaDart.start(appId: 'YOUR-APP-ID');
updates?.stopAutomaticUpdates();
updates?.startAutomaticUpdates(const UpdatePolicy(automatic: true, interval: Duration(hours: 12)));
print(updates?.automaticUpdatesEnabled);
```

The default interval can also be set per app in `otadart.yaml` (`update: check_interval_seconds: 3600`).

## Step by step

If you want full control instead of `OtaDart.start`:

```dart
final updates = await OtaDart.tryInitialize(appId: 'YOUR-APP-ID');
if (updates != null) {
  await updates.markCurrentBootHealthy();   // this launch works
  await updates.update();                   // download a patch if there is one
}
```

## Version and patch number

```dart
final info = await updates.info();
print(info.label);            // 1.2.0+5 · patch #3
print(info.releaseVersion);   // 1.2.0+5
print(info.currentPatch);     // Patch #3   (null = store build)
print(info.nextPatch);        // Patch #4 after a download, until the next launch
print(info.track);            // stable
print(info.platform);         // android

final patch = await updates.currentPatch();   // OtaPatch? — number running now
final next = await updates.nextPatch();       // OtaPatch? — applies on next launch
```

## Check without downloading

```dart
final offer = await updates.availableUpdate();
switch (offer.availability) {
  case UpdateAvailability.patchAvailable:    // patch #offer.patchNumber, offer.downloadBytes
  case UpdateAvailability.rollbackAvailable: // track rolled back to the store build
  case UpdateAvailability.readyOnNextLaunch: // already downloaded — restart to apply
  case UpdateAvailability.upToDate:
}
```

## Download progress

```dart
updates.progress.listen((p) {
  // p.phase: checking, downloading, reconstructing, ready, upToDate, failed
  // p.fraction: 0.0–1.0 while downloading
});
final result = await updates.update();
if (result.readyOnNextLaunch) { /* ask the user to restart */ }
```

## API

| Member | What it does |
| --- | --- |
| `OtaDart.start(appId:, …)` | Recommended setup in one call: check now and on a schedule, confirm the launch |
| `OtaDart.tryInitialize(appId:)` | Connect, or `null` when updates aren't available in this build |
| `OtaDart.initialize(appId:)` | Connect; throws `OtaDartException` when not available |
| `OtaDart.isSupported()` | `true` when this build can receive patches |
| `info()` | Version, patch numbers, track, platform and health in one call |
| `currentPatch()` / `nextPatch()` | Patch running now / patch applied on next launch |
| `availableUpdate()` | What the service offers, without downloading |
| `update()` / `checkForUpdate()` | Download and stage a patch; applies on next launch |
| `progress` / `currentProgress` | Update progress events |
| `startAutomaticUpdates(policy)` / `stopAutomaticUpdates()` | Turn scheduled checks on / off |
| `automaticUpdatesEnabled` | `true` while scheduled checks are on |
| `markCurrentBootHealthy()` | Confirm this launch works (enables automatic fallback) |
| `canRestart` / `restart()` | Web only: reload the page onto the newest build |
| `track`, `appId`, `releaseVersion` | Build details, available instantly |
| `close()` | Release resources |

## Web

Flutter web works with the same code. There are no patches on the web — you deploy a new build — but open tabs keep running the old one. On the web `OtaDart` compares the running build with the `version.json` that `flutter build web` writes, and tells you when a newer build is live:

```dart
final updates = await OtaDart.tryInitialize(appId: 'YOUR_APP_ID');
final offer = await updates?.availableUpdate();
if (offer != null && offer.hasUpdate) {
  // e.g. show "A new version (${offer.version}) is available — Reload"
  if (updates!.canRestart) await updates.restart(); // reloads the page
}
```

`info().label` reads like `1.2.0+5 · web`. `startAutomaticUpdates` checks on a schedule here too. Serve `version.json` without long caching so new deploys are seen.

## Requirements

**Flutter version.** Each Flutter version has its own OTADart engine. Supported now: **3.50.1** (Android and iOS) and **3.47.9** (Android). The live list: `otadart flutter versions list`. Need another version? Request it at https://otadart.dev/#/support/flutter. Build with any of them, whatever Flutter is installed on your computer:

```sh
otadart flutter use 3.47.9   # this app builds with Flutter 3.47.9
otadart flutter use path     # back to the Flutter on your PATH
```

That sets `flutter_version: 3.47.9` in `otadart.yaml` (you can edit it there too), or use `--flutter-version 3.47.9` for one command. OTADart downloads that Flutter once (into `~/.otadart/flutter/`) and builds with it; the Flutter on your PATH is not changed. Patches always use the Flutter version their release was built with.

Patches apply to app builds made with `otadart release`. Dart code and assets (images, fonts, other files) ship in a patch; native code, plugins and permissions need a store release. The track a build listens to is set when it is released.

## Links

- Docs: https://otadart.dev/docs/sdk
- Support: https://otadart.dev/support
