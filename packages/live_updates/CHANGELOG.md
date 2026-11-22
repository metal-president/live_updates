## Unreleased

- **Breaking:** `AndroidLiveUpdateOptions.requestPromotion` is replaced by
  `mode` (`AndroidLiveUpdateMode.liveUpdate`, `ongoing`, `classic`).
  `requestPromotion: false` becomes `mode: AndroidLiveUpdateMode.ongoing`;
  `classic` shows the same notification as Android 15 and earlier on every
  version. Remote payloads with `requestPromotion: false` still work.
- `IosLiveUpdateOptions.color`, `backgroundColor` and `foregroundColor`:
  accent, Lock Screen background and text of the generated widget
  (content-state keys `tintArgb` / `backgroundArgb` / `foregroundArgb`); the
  Always-On display uses system colors. Run
  `create_widget` to update `LiveUpdatesViews.swift`.

## 0.0.6

- Docs: clearer platform table (Live Activity push tokens, buttons, images,
  remote updates, broadcasts), requirements, `end(dismissAfter:)` on Android,
  and complete push-to-start keys.

## 0.0.5

- `LiveUpdate.key`: the key from `startOrUpdate`, a push-to-start
  `attributes.key` (iOS) or a remote `live_updates_id` (Android), also on
  updates from `active()` and `onStarted`.
- Docs: sending to both platforms through FCM (`docs/server-fcm.md`).
- `IosLiveUpdateOptions.compactTrailing` and `minimal` (`IosIslandContent`):
  choose what the compact and minimal Dynamic Island show.
- `create_widget`: the reusable views move to `LiveUpdatesViews.swift`, which
  `create_widget` always updates together with `LiveUpdatesAttributes.swift`
  and `LiveUpdatesActionIntent.swift`. Your layout file is kept unless you pass
  `--force`. Existing layouts keep working; run `create_widget --force` once
  to switch to the shorter layout that uses the shared views (needed for
  `compactTrailing` / `minimal`). `LiveUpdatesActionIntent.swift` is now
  always replaced; a file without the generated header is kept as `.bak`.
- Screenshots on pub.dev and in the README; the example app has its own icon.

## 0.0.4

- `LiveUpdateContent.timer`: a countdown or stopwatch counted by the system
  (iOS widget template, Android chronometer). Re-run
  `create_widget --force` to update the widget.
- Android: `progressSegments`, `progressPoints` and `progressTrackerIcon`
  (Android 16+ `ProgressStyle`), `timeoutAfter` and `alert`.
- Docs: Android 17 does not show the body text of a Live Update with
  `metrics`.

## 0.0.3

- iOS 18 broadcast: `start(..., iosChannelId:)` and `startOrUpdate(...,
  iosChannelId:)` subscribe a Live Activity to an APNs broadcast channel.
- `tool/send_push.dart`: `apns-channel` (create, list, delete) and
  `apns-broadcast` commands; `--input-push-channel` and `--activity-key` for
  push-to-start.
- `create_widget`: per-configuration widget bundle ids and App Groups for
  flavors (`LIVE_UPDATES_APP_GROUP` build setting); offers to install the
  xcodeproj gem when it is missing; manual setup steps in the README.
- `LiveUpdates.setBackgroundActionHandler`: handle button presses while the
  app is not running in a headless Flutter engine (Android and iOS).
  Re-run `create_widget --force` to update `LiveUpdatesActionIntent.swift`.
- `LiveUpdateAction.requiresUnlock`: ask for an unlock before a Lock Screen
  press is handled (iOS, Android 12+).
- Android 17: `AndroidLiveUpdateOptions.metrics` (`MetricStyle`, with
  `criticalMetric`) and semantic colors for the body, the progress bar and
  metrics (`LiveUpdateSemanticStyle`).
- iOS 27: the generated widget leaves the title out of the compact Dynamic
  Island view when it is limited in width (landscape). Re-run
  `create_widget --force` to update the widget.
- Fix: an Android `channelId` option no longer affects iOS push settings.

## 0.0.2

- Push tokens (`LiveUpdate.pushTokens`, `LiveUpdates.pushToStartTokens`)
  replay the current token to new listeners.
- `LiveUpdatePushToken.toString()` no longer includes the token.

## 0.0.1

- Initial release.
- Start, update and end iOS Live Activities and Android Live Updates with one API.
- iOS: FFIgen bindings to an ActivityKit bridge, push-to-start and push token
  streams, `create_widget` command generating a SwiftUI widget extension.
- Android: JNIgen bindings; ongoing notifications with `ProgressStyle` on
  Android 16+ and promotion to Live Updates where supported, progress bar
  fallback below; remote payloads; `canPostPromotedNotifications()`.
- Tap routes, notification permission request, no-op on other platforms.
- Images (`LiveUpdateImage`) shared with the iOS widget through an App Group
  and shown as the Android large icon.
- `endAll()`, `onStarted` and `LiveUpdate.states`.
- `startOrUpdate(key, content)` and `find(key)` for app-chosen keys.
- Buttons (`LiveUpdateAction`) with background or open-app handling and
  `onAction` / `LiveUpdate.actions`.
