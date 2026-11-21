# live_updates_fcm

Firebase Cloud Messaging integration for [`live_updates`](https://pub.dev/packages/live_updates).

- **Android:** FCM data messages with `live_updates_*` keys start, update and
  end Live Update notifications, in the foreground and in the background.
- **iOS:** Live Activities are updated by APNs directly. Send the tokens from
  `LiveUpdates.pushToStartTokens` and `LiveUpdate.pushTokens` to your server
  and deliver through APNs or FCM's `apns.live_activity_token`.

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
| `activity` (with `updateId`) | iOS | `message.apns.live_activity_token`, `"event": "update"` / `"end"` |

```dart
LiveUpdatesFcm.tokens().listen((token) {
  api.registerToken(
    type: token.type.name,
    value: token.value,
    updateId: token.updateId,
  );
});
// The installation ID is reported once the app registers with FCM.
await FirebaseMessaging.instance.register();
```

Keep the latest token per type (and per `updateId`). Activity tokens are
emitted for live updates started with `pushUpdates: true`. Tokens allow
pushing to the device, so send them over an authenticated connection and do
not log them; `LiveUpdatesToken.toString()` leaves the value out.

## Message format

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
| `live_updates_content` | JSON string with `title`, `body`, `progress`, `iconName`, `route` and Android options |
| `live_updates_dismiss_after` | Optional, seconds to keep the final content on `end` |

`packages/live_updates/tool/send_push.dart` in the repository sends these
messages for testing.

## License

MIT
