# Sending live updates from a server with FCM

With FCM HTTP v1 a server reaches both platforms through one API and one
service account (upload the APNs key to Firebase for iOS). The content is the
same JSON on both platforms; only the envelope around it differs.

## What the app sends to the server

Register the tokens from `LiveUpdatesFcm.tokens()` (see the
[`live_updates_fcm` README](../packages/live_updates_fcm/README.md)):

| Token type | Store as | Used for |
| --- | --- | --- |
| `fcmInstallationId` | device | Every message (`message.fid`) |
| `pushToStart` | device (iOS) | Starting a Live Activity remotely |
| `activity` | device + `key` (iOS) | Updating or ending that Live Activity |

Use your own id as the key, such as an order number: pass it to
`LiveUpdates.startOrUpdate(key, ...)` in the app, or set it when starting
remotely. Activity tokens arrive with that `key`, so the server can address
the update by the same id on both platforms. Keys appear in notification data
and push payloads, so do not use secrets as keys.

The app reports tokens and keys itself, so a modified app can report any key.
On the server:

- Accept tokens only over an authenticated connection, and store them per
  user, device and key. A new token for the same key replaces the old one.
- Look keys up only within the records of the user they belong to, after
  checking that the user owns that order (or other object). Never map a key
  to another user's token.
- Use a key for one running update per device: two activities started with
  the same key report two tokens.

## One content JSON

Build the content once. Keys are those of `LiveUpdateContent` (see the
package README): `title`, `body`, `progress`, `route`, `timerEnd` /
`timerStart` (seconds since 1970), `metrics`, `steps`, `journey`, `actions`,
`extra`, Android options such as `channelId`, `shortCriticalText` or
`progressSegments`, and the iOS options `layout` / `compactLeading` /
`compactTrailing` / `minimal` / `tintArgb` / `backgroundArgb` /
`foregroundArgb`. Each platform ignores the keys it does not use. iOS
requires `title`, and `extra` must map strings to strings, or the activity
rejects the content.

Icons are objects with exactly one of `native` (a drawable on Android, an
asset catalog image of the widget on iOS), `asset` (a Flutter asset; on iOS
only one the app stored with `LiveUpdates.preloadIcons`) or `symbol` (an SF
Symbols name, iOS only). An object with several of these keys uses the
first of `native`, `asset`, `symbol`. An icon that cannot be shown falls back
to the platform default (see Icons in the package README).

| Key | Dart | Platform |
| --- | --- | --- |
| `icon` | `LiveUpdateContent.icon` | both |
| `iosIcon` | `IosLiveUpdateOptions.icon` | iOS |
| `islandIcon` | `IosLiveUpdateOptions.islandIcon` | iOS |
| `androidSmallIcon` | `AndroidLiveUpdateOptions.smallIcon` | Android |
| `progressTrackerIcon` | `AndroidLiveUpdateOptions.progressTrackerIcon` | Android |
| `actions[].icon`, `actions[].iosIcon`, `actions[].androidIcon` | `LiveUpdateAction.icon`, `iosIcon`, `androidIcon` | as named |

Each action also has `id`, `title` and optionally `opensApp` and
`requiresUnlock` (booleans).

```json
{
  "title": "Order #1234",
  "icon": {"asset": "assets/icons/parcel.png"},
  "islandIcon": {"symbol": "shippingbox.fill"},
  "androidSmallIcon": {"native": "ic_stat_parcel"},
  "actions": [{"id": "cancel", "title": "Cancel", "icon": {"symbol": "xmark"}}]
}
```

```json
{"title": "Order #1234", "body": "On the way", "progress": 0.6, "timerEnd": 1893456000}
```

With a layout and its data (`steps.current` is an index into `labels`):

```json
{
  "title": "Order #1234",
  "progress": 0.6,
  "layout": "stepper",
  "steps": {"labels": ["Ordered", "Preparing", "On the way", "Delivered"], "current": 2}
}
```

## Android envelope

A data message to the device. FCM data values are strings, so the content is
JSON encoded once more.

```json
{
  "message": {
    "fid": "<fcmInstallationId>",
    "android": {"priority": "high"},
    "data": {
      "live_updates_event": "update",
      "live_updates_id": "order-1234",
      "live_updates_content": "{\"title\":\"Order #1234\",\"body\":\"On the way\",\"progress\":0.6,\"timerEnd\":1893456000}"
    }
  }
}
```

- `live_updates_event`: `start`, `update` or `end`. `live_updates_id` is the key.
- `end` may carry final content and `live_updates_dismiss_after` (seconds,
  as a string like every FCM data value). Without it the final content stays
  until the user dismisses it. Final content is shown only for an update that
  is still shown; an `end` for one the user dismissed just ends it.
- An `update` for an update that is not shown (ended, or dismissed by the
  user) is ignored; send `start` to show it again.

## iOS envelope

The same content as a JSON object in `content-state`, addressed with the
activity token for that key (or the push-to-start token to start one).

```json
{
  "message": {
    "fid": "<fcmInstallationId>",
    "apns": {
      "live_activity_token": "<activity token for order-1234>",
      "headers": {"apns-priority": "10"},
      "payload": {
        "aps": {
          "timestamp": 1893455400,
          "event": "update",
          "content-state": {"title": "Order #1234", "body": "On the way", "progress": 0.6, "timerEnd": 1893456000}
        }
      }
    }
  }
}
```

- `timestamp` is the current time in seconds; ActivityKit ignores pushes
  older than the last one it applied.
- `start` (with the push-to-start token) also needs
  `"attributes-type": "LiveUpdatesAttributes"`, `"attributes": {"key": "order-1234"}`
  and an `alert` with `title` and `body`. Use a key that no running activity
  on the device has.
- `end` takes `dismissal-date` (a UNIX time in seconds); `stale-date`
  (also a UNIX time), `relevance-score` and
  `alert` go next to `content-state`, not inside it.
- A push replaces the whole content state: send every field that should stay,
  including `extra`, `layout`, `metrics`, `steps`, `journey`,
  `compactTrailing` and `minimal`.
- Delete the activity token once the update has ended; it cannot be used
  again.

## Summary of the differences

| | Android | iOS |
| --- | --- | --- |
| Address | `fid` + `live_updates_id` (key) | activity token for the key (push-to-start token for `start`) |
| Content | `data.live_updates_content` (string) | `apns.payload.aps.content-state` (object) |
| Event | `data.live_updates_event` | `aps.event` + `aps.timestamp` |
| Final display time | `live_updates_dismiss_after` (seconds from now) | `aps.dismissal-date` (time) |
| Many devices at once | FCM topics | broadcast channels (iOS 18, APNs only) |

`tool/send_push.dart` builds both envelopes (`fcm` and `fcm-ios` commands);
see [testing-remote.md](testing-remote.md) for running it.
