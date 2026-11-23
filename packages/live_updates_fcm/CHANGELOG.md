## Unreleased

- Docs: README adds getting started steps, the imports of the example and
  which tokens each platform needs.

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
