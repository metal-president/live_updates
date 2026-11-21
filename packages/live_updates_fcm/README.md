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

## Message format

Send a data message (no `notification` block) with high priority:

```json
{
  "message": {
    "token": "<FCM registration token>",
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
