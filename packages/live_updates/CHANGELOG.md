## Unreleased

- iOS 18 broadcast: `start(..., iosChannelId:)` and `startOrUpdate(...,
  iosChannelId:)` subscribe a Live Activity to an APNs broadcast channel.
- `tool/send_push.dart`: `apns-channel` (create, list, delete) and
  `apns-broadcast` commands; `--input-push-channel` and `--activity-key` for
  push-to-start.

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
