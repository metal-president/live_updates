# live_updates_fcm

Remote updates for [`live_updates`](https://pub.dev/packages/live_updates)
through Firebase Cloud Messaging. Use it if your app already uses FCM;
live_updates works without it.

- **Android:** applies FCM data messages with `live_updates_*` keys that
  start, update and end live updates, in the foreground and in the
  background.
- **iOS:** reports the Live Activity push tokens your server needs. The
  system applies Live Activity pushes itself, so the app handles no messages.
  Send them through FCM (`apns.live_activity_token`) or directly through APNs.

## Getting started

1. Set up [`live_updates`](https://pub.dev/packages/live_updates#getting-started)
   (on iOS, including the widget extension and the Push Notifications
   capability).
2. Set up Firebase and
   [`firebase_messaging`](https://pub.dev/packages/firebase_messaging) as
   usual.
3. Turn on Firebase Installation IDs, which `LiveUpdatesFcm.tokens()`
   reports (they are off by default):

   - Android, inside `<application>` in `android/app/src/main/AndroidManifest.xml`:

     ```xml
     <meta-data
         android:name="firebase_messaging_installation_id_enabled"
         android:value="true" />
     ```

   - iOS, in `ios/Runner/Info.plist`:

     ```xml
     <key>FirebaseMessagingInstallationIdEnabled</key>
     <true/>
     ```

4. Add the package:

   ```bash
   flutter pub add live_updates_fcm
   ```

On Android 13 and later, live updates appear only after the user grants the
notification permission (`LiveUpdates.requestPermission()`), including ones
started by a message.

## Usage

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:live_updates_fcm/live_updates_fcm.dart';

@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  await LiveUpdatesFcm.handleMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  // Handle foreground messages. onError receives live_updates payloads that
  // could not be applied.
  LiveUpdatesFcm.listen(onError: (e, _) => debugPrint('$e'));
  runApp(const App());
}
```

`handleMessage` returns `false` for messages that are not live_updates
messages, so you can chain your own handling.

## Registering tokens with your server

Android needs only the installation ID. iOS also needs the push-to-start
token (to start from your server) and an activity token for each live update
started with `pushUpdates: true` (to update or end it).
`LiveUpdatesFcm.tokens()` merges them into one stream:

| Type | Platform | Send with |
| --- | --- | --- |
| `fcmInstallationId` | Android, iOS | `message.fid` |
| `fcmRegistrationToken` (opt-in, legacy) | Android, iOS | `message.token` |
| `pushToStart` | iOS 17.2+ | `message.apns.live_activity_token`, `"event": "start"`, together with `message.fid` |
| `activity` (with `updateId` and `key`) | iOS | `message.apns.live_activity_token`, `"event": "update"` / `"end"`, together with `message.fid` |

The Live Activity tokens do not address the device on their own: an iOS
message also needs a target: the installation ID (`message.fid`), or
`message.token` if you use the legacy registration token instead, as in
[docs/server-fcm.md](https://github.com/metal-president/live_updates/blob/main/docs/server-fcm.md#ios-envelope).

`fcmRegistrationToken` is only for apps that cannot use installation IDs
yet. Firebase does not issue registration tokens while installation IDs are
turned on (step 3 of [Getting started](#getting-started)), so
`tokens(includeRegistrationToken: true)` reports an error instead of a token
in that setup. Use one of the two, not both.

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
// The installation ID is reported once the app registers with FCM, which
// happens on its own unless auto-init is turned off; then register:
await FirebaseMessaging.instance.register();
```

Keep the latest token per type (and per `updateId`), and drop an activity
token when its live update ends. Each activity token carries the update's
`key` (the key given to `startOrUpdate`, or `attributes.key` of a
push-to-start), so your server can match it with the `live_updates_id` it
sends to Android. A new subscription first receives the tokens already known.

On iOS, Live Activity pushes count toward a per-hour budget; see
[Platform limits](https://pub.dev/packages/live_updates#platform-limits)
for `apns-priority` and frequent updates.

Tokens allow pushing to the device: send them over an authenticated
connection, store them per authenticated user and device on your server (the
client chooses `updateId` and `key`, so do not trust them across users), and
do not log them. `LiveUpdatesToken.toString()` and
`LiveUpdatePushToken.toString()` leave the value out.

## Message format

[docs/server-fcm.md](https://github.com/metal-president/live_updates/blob/main/docs/server-fcm.md)
shows complete messages for both platforms. For Android, send a data message
(no `notification` block) with high priority:

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

High priority lets the message wake the device, but Firebase Cloud
Messaging can lower the priority of an app's later messages when high
priority messages often show nothing to the user. Send high priority only
for messages that start or visibly change a live update, and stop sending
updates for a live update that the user dismissed (the app ignores them).
The app has a few seconds to handle each message, which is enough for
`handleMessage` but not for extra network calls in the same handler.
([source](https://firebase.google.com/docs/cloud-messaging/android-message-priority))

[`tool/send_push.dart`](https://github.com/metal-president/live_updates/blob/main/packages/live_updates/tool/send_push.dart)
sends these messages for testing.

## License

MIT
