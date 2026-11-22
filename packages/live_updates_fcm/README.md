# live_updates_fcm

Firebase Cloud Messaging integration for [`live_updates`](https://pub.dev/packages/live_updates).

- **Android:** FCM data messages with `live_updates_*` keys start, update and
  end Live Update notifications, in the foreground and in the background.
- **iOS:** the system applies Live Activity pushes itself, so the app needs no
  message handling. Send the tokens from `LiveUpdatesFcm.tokens()` to your
  server and push through FCM (`apns.live_activity_token`) or APNs directly.

## Usage

Set up [`firebase_messaging`](https://pub.dev/packages/firebase_messaging) as
usual, then:

```dart
import 'package:live_updates_fcm/live_updates_fcm.dart';

@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  await LiveUpdatesFcm.handleMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  LiveUpdatesFcm.listen(); // foreground messages
  runApp(const App());
}
```

`handleMessage` returns `false` for messages that are not live_updates
messages, so you can chain your own handling.

## Registering tokens with your server

`LiveUpdatesFcm.tokens()` merges everything your server needs into one
stream:

| Type | Platform | Send with |
| --- | --- | --- |
| `fcmInstallationId` | all | `message.fid` |
| `fcmRegistrationToken` (opt-in, legacy) | all | `message.token` |
| `pushToStart` | iOS 17.2+ | `message.apns.live_activity_token`, `"event": "start"` |
| `activity` (with `updateId` and `key`) | iOS | `message.apns.live_activity_token`, `"event": "update"` / `"end"` |

```dart
LiveUpdatesFcm.tokens().listen(
  (token) => api.registerToken(
    type: token.type.name,
    value: token.value,
    updateId: token.updateId,
    key: token.key, // your id from startOrUpdate or push-to-start
  ),
  // Token sources can fail (for example before APNs is ready on iOS).
  onError: (Object error) => debugPrint('Token error: $error'),
);
// The installation ID is reported once the app registers with FCM.
await FirebaseMessaging.instance.register();
```

Keep the latest token per type (and per `updateId`), and drop an activity
token once that live update ends. Activity tokens carry the update's `key`
(the key given to `startOrUpdate`, or `attributes.key` of a push-to-start), so
your server can find the iOS token for the same id it sends to Android as
`live_updates_id`. Activity tokens are emitted for live
updates started with `pushUpdates: true`. A new subscription first receives
the tokens that are already known.

Tokens allow pushing to the device: send them over an authenticated
connection, store them per authenticated user and device on your server (the
client chooses `updateId` and `key`, so do not trust them across users), and do not log
them. `LiveUpdatesToken.toString()` and `LiveUpdatePushToken.toString()`
leave the value out.

## Message format

For a server that sends to both platforms through FCM, see
[docs/server-fcm.md](https://github.com/metal-president/live_updates/blob/main/docs/server-fcm.md).

Send a data message (no `notification` block) with high priority:

```json
{
  "message": {
    "fid": "<Firebase Installation ID>",
    "android": { "priority": "high" },
    "data": {
      "live_updates_event": "update",
      "live_updates_id": "order-1",
      "live_updates_content": "{\"title\":\"Order #1\",\"progress\":0.6}"
    }
  }
}
```

| Key | Value |
| --- | --- |
| `live_updates_event` | `start`, `update` or `end` |
| `live_updates_id` | Your id; later messages with the same id update the same notification |
| `live_updates_content` | JSON string with the keys of `LiveUpdateContent` (`title`, `body`, `progress`, `timerEnd`, `actions`, ...) and Android options |
| `live_updates_dismiss_after` | Optional, seconds to keep the final content on `end` (without it, it stays until dismissed) |

`packages/live_updates/tool/send_push.dart` in the repository sends these
messages for testing.

## License

MIT
