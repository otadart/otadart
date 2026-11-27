## 0.1.0-beta.5

- README: OTADart is free and unlimited.

## 0.1.0-beta.4

- README: Flutter versions — see the supported ones with `otadart flutter versions list`, switch with `otadart flutter use <version>`; patches keep their release's Flutter version.

## 0.1.0-beta.3

- `OtaDart.start(appId: …)`: the recommended setup in one line — checks at launch and every 6 hours, confirms the launch so a crashing patch rolls back.
- Automatic checks can be turned on or off and timed: `checkOnLaunch`, `firstCheckAfter`, `autoCheck`, `checkEvery`, `healthyAfter`; `automaticUpdatesEnabled` at runtime.
- `otadart init` adds `OtaDart.start` to `lib/main.dart` for you.

## 0.1.0-beta.2

- Documented free self-hosting and linked the setup guide.

## 0.1.0-beta.1

- First beta: Android and iOS releases and patches work end to end on real phones.
- README: how to try releases and patches on the iOS Simulator and Android emulator (`otadart release ios --simulator`).
- README: what OTADart does, measured on a real iPhone 17 Pro and Samsung Galaxy A15.
