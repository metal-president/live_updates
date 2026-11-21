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
