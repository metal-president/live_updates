## 0.3.0

- Requires live_updates 0.3.0 (scheduled live updates, `endAt` and
  `endedContent`). Android live updates are now removed after 8 hours by
  default; remote payloads take `maxDurationMillis` (`0` for no limit, see
  docs/server-fcm.md and Upgrading in the live_updates README).
- Docs: turning on installation IDs applies to the whole app: Firebase stops
  issuing registration tokens, so check other SDKs that use them first.

## 0.2.1

- Requires live_updates 0.2.1, so remote payloads can carry `publicContent`
  (content for a locked device that hides sensitive content) and
  `"androidLockScreenVisibility": "secret"` (see docs/server-fcm.md).

## 0.2.0

- Requires live_updates 0.2.0, whose icons are `LiveUpdateIcon` values. In
  remote payloads, icons are objects such as `{"native": "ic_stat"}` (see
  docs/server-fcm.md).

## 0.1.3

- Requires live_updates 0.1.3, so apps can target iOS 15.0. Below iOS 17.2,
  `tokens()` reports only the Firebase tokens (no Live Activity tokens).
- Docs: the token table marks the `activity` token as iOS 17.2+.

## 0.1.2

- Docs: Firebase does not issue registration tokens while installation IDs
  are turned on, so `tokens(includeRegistrationToken: true)` reports an error
  for that token in this setup. The README, dartdoc and a code comment now
  say so (no behavior change).
- Docs: the token table lists Android and iOS instead of "all", and says that
  Live Activity messages also need a target (`message.fid`, or
  `message.token` with the legacy registration token).
- Docs: README notes that Firebase Cloud Messaging can lower the priority of
  high priority messages that show nothing to the user, and that iOS Live
  Activity pushes count toward a per-hour budget.

## 0.1.1

- Docs: README adds getting started steps, including turning on Firebase
  Installation IDs (Android manifest and iOS Info.plist keys) that
  `LiveUpdatesFcm.tokens()` needs, the notification permission, the imports
  of the example and which tokens each platform needs.

## 0.1.0

- `LiveUpdatesFcm.listen(onError:)`: a live_updates message that cannot be
  applied is reported instead of becoming an uncaught error.
- Requires live_updates 0.1.0.

## 0.0.6

- Docs: clearer iOS description and content keys.
- Requires live_updates 0.0.6.

## 0.0.5

- `LiveUpdatesToken.key`: activity tokens carry the update's key, so a server
  can find the iOS token for the id it uses on Android.
- Example for pub.dev, package topics.
- Requires live_updates 0.0.5.

## 0.0.4

- Requires live_updates 0.0.4 (timers, Android progress stages, timeout
  and alerts).

## 0.0.3

- Requires live_updates 0.0.3 (iOS 18 broadcast, background button
  handler, Android 17 metrics).

## 0.0.2

- `LiveUpdatesFcm.tokens()`: one stream with every token your server needs —
  the Firebase Installation ID (or, opt-in, the legacy registration token)
  and, on iOS, push-to-start and per-activity Live Activity push tokens.
- Requires live_updates 0.0.2.

## 0.0.1

- Initial release: forwards FCM data messages to `LiveUpdates.handleRemotePayload`.
