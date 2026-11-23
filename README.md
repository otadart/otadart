# otadart

Connect your Flutter app to [OTADart](https://otadart.dev) — over-the-air Dart updates for Android and iOS.

Your app checks for a signed patch, downloads it in the background, and applies it the next time it opens. If a patched launch fails, it falls back automatically.

## Install

```sh
flutter pub add otadart
```

`otadart init` adds it for you. Install the CLI with:

```sh
curl -fsSL https://otadart.dev/install.sh | bash
```

## Quick start

```dart
import 'package:otadart/otadart.dart';

final updates = await OtaDart.tryInitialize(appId: 'YOUR-APP-ID'); // from otadart.yaml
if (updates != null) {
  await updates.markCurrentBootHealthy();   // this launch works
  await updates.update();                   // download a patch if there is one
}
```

`tryInitialize` returns `null` in `flutter run` and in builds not made with `otadart release`, so the same code is safe everywhere.

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

## Automatic checks

```dart
updates.startAutomaticUpdates(const UpdatePolicy(automatic: true, interval: Duration(hours: 6)));
```

## API

| Member | What it does |
| --- | --- |
| `OtaDart.tryInitialize(appId:)` | Connect, or `null` when updates aren't available in this build |
| `OtaDart.initialize(appId:)` | Connect; throws `OtaDartException` when not available |
| `OtaDart.isSupported()` | `true` when this build can receive patches |
| `info()` | Version, patch numbers, track, platform and health in one call |
| `currentPatch()` / `nextPatch()` | Patch running now / patch applied on next launch |
| `availableUpdate()` | What the service offers, without downloading |
| `update()` / `checkForUpdate()` | Download and stage a patch; applies on next launch |
| `progress` / `currentProgress` | Update progress events |
| `startAutomaticUpdates(policy)` / `stopAutomaticUpdates()` | Check on a schedule |
| `markCurrentBootHealthy()` | Confirm this launch works (enables automatic fallback) |
| `track`, `appId`, `releaseVersion` | Build details, available instantly |
| `close()` | Release resources |

## Requirements

Patches apply to app builds made with `otadart release`. Native code, plugins, permissions and assets need a store release. The track a build listens to is set when it is released.

## Links

- Docs: https://otadart.dev/docs/sdk
- Support: https://otadart.dev/support
