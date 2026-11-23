# otadart

Connect your Flutter app to [OTADart](https://otadart.dev) — over-the-air Dart updates for Android and iOS.

Your app checks for a signed patch, downloads it in the background, and applies it the next time it opens. If a patched launch fails, it falls back automatically.

## Install

```sh
flutter pub add otadart
```

The `otadart` CLI adds it for you when you run `otadart init`. Install the CLI with:

```sh
curl -fsSL https://otadart.dev/install.sh | bash
```

## Use

```dart
import 'package:otadart/otadart.dart';

final updates = await OtaDart.initialize(appId: 'YOUR-APP-ID'); // from otadart.yaml

updates.progress.listen((p) => print(p.phase));   // optional: show progress

final result = await updates.checkForUpdate();
if (result.readyOnNextLaunch) {
  // Patch staged — it applies on the next launch.
}

// Once your app reaches a working screen:
await updates.markCurrentBootHealthy();
```

Check automatically instead:

```dart
updates.startAutomaticUpdates(const UpdatePolicy(automatic: true));
```

## API

| Member | What it does |
| --- | --- |
| `OtaDart.initialize(appId:)` | Connect to the update service for this app |
| `checkForUpdate()` | Check, download and verify a patch now |
| `progress` / `currentProgress` | Update progress events |
| `startAutomaticUpdates(policy)` | Check on a schedule |
| `markCurrentBootHealthy()` | Confirm this launch works (enables automatic fallback) |
| `close()` | Release resources |

## Requirements

Patches apply to app builds made with `otadart release`. Native code, plugins, permissions and assets need a store release.

## Links

- Docs: https://otadart.dev/docs/quick-start
- Support: https://otadart.dev/support
