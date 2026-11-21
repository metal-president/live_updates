## Unreleased

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
