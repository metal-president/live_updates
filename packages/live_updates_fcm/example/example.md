# live_updates_fcm example

Forward live update messages from Firebase Cloud Messaging and register the
tokens your server needs. Set up `firebase_messaging` for your app first
(Firebase project, `google-services.json`, `GoogleService-Info.plist`, and the
APNs key uploaded to Firebase for iOS).

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates_fcm/live_updates_fcm.dart';

// Runs in a background isolate for messages that arrive while the app is in
// the background or not running.
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  await LiveUpdatesFcm.handleMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  LiveUpdatesFcm.listen(); // messages while the app is in the foreground

  await LiveUpdates.requestPermission();
  // Send every token to your server over an authenticated connection.
  LiveUpdatesFcm.tokens().listen(
    (token) => sendToServer({
      'type': token.type.name,
      'value': token.value,
      'updateId': token.updateId,
      'key': token.key, // your id for the update (iOS activity tokens)
    }),
    onError: (Object error) => debugPrint('Token error: $error'),
  );
  await FirebaseMessaging.instance.register();

  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Ready')))));
}

Future<void> sendToServer(Map<String, Object?> token) async {
  // Your API call.
}
```

The server then sends data messages such as:

```json
{
  "message": {
    "fid": "<fcmInstallationId>",
    "android": {"priority": "high"},
    "data": {
      "live_updates_event": "update",
      "live_updates_id": "order-1234",
      "live_updates_content": "{\"title\":\"Order #1234\",\"progress\":0.6}"
    }
  }
}
```

See the package README for the full message format and the iOS tokens.
