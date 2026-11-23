## 0.1.0-dev.2

- `info()`: release version, current and next patch number, track, platform, health — in one call.
- `currentPatch()` and `nextPatch()`.
- `availableUpdate()`: check what's offered without downloading.
- `update()`: download and stage (same as `checkForUpdate()`).
- `OtaDart.tryInitialize()` and `OtaDart.isSupported()`: safe in `flutter run` and plain builds.
- `track`, `appId`, `releaseVersion` getters.

## 0.1.0-dev.1

- First preview: connect with `OtaDart.initialize`, check for patches, progress events, automatic checks and launch health confirmation.
