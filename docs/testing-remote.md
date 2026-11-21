# Verifying remote updates

This guide walks through checking push-driven live updates end to end with the
example app and `packages/live_updates/tool/send_push.dart`.

The sender only needs the Dart SDK, `openssl` and `curl` (APNs requires HTTP/2,
which `dart:io` does not support). Add `--dry-run` to any command to print the
request without sending it.

## Automated coverage

| What | Where |
| --- | --- |
| Dart content to JSON (shared wire format) | `packages/live_updates/test/serialization_test.dart` |
| Widget `LiveUpdatesAttributes` matches the plugin | `packages/live_updates/test/widget_template_test.dart` |
| FCM message forwarding | `packages/live_updates_fcm/test/` |
| Android `handleRemotePayload` start/update/end | `packages/live_updates/example/integration_test/` (run with `tool/integration_test_android.sh`) |

APNs and FCM delivery itself needs real credentials, so it is verified manually
with the steps below.

## iOS with APNs

### Prerequisites

- An Apple Developer account, the example's bundle id
  (`com.ttechapp.liveUpdatesExample`, change it to one you own) and an APNs
  auth key (`AuthKey_<KEYID>.p8`) with its Key ID and your Team ID.
- The **Push Notifications** capability on the Runner target, and a signing
  team for both Runner and LiveUpdatesWidget.
- A physical iPhone is the most reliable target. Simulators on Apple silicon
  can receive remote pushes from the APNs sandbox, but Live Activity push
  support there varies by Xcode version; if a push returns HTTP 200 and nothing
  appears, retry on a device.

### Steps

1. Run the example in debug (APNs sandbox) and turn on **Request push token**.
2. The log shows `push-to-start: <hex>` shortly after launch.
3. Start an activity remotely:

   ```bash
   cd packages/live_updates
   dart run tool/send_push.dart apns --sandbox \
     --team-id <TEAM_ID> --key-id <KEY_ID> --key AuthKey_<KEY_ID>.p8 \
     --bundle-id com.ttechapp.liveUpdatesExample \
     --token <push-to-start token> --event start \
     --alert-title "Order placed" \
     --content '{"title":"Order #1","body":"Preparing","progress":0.1,"route":"/orders/1"}'
   ```

   Expect `HTTP 200` and a Live Activity on the Lock Screen / Dynamic Island.
   Add `"key"` to the `attributes` (the sender sends `{}`; edit `_aps` to
   include it) to find the activity later with `LiveUpdates.find`.
4. Back in the app, tap **Active** to see the remotely started activity, or
   start one with **Start**; the log shows `push token: <hex>`.
5. Update and end it with the per-activity token:

   ```bash
   dart run tool/send_push.dart apns --sandbox ... --token <push token> \
     --event update --content '{"title":"Order #1","body":"On the way","progress":0.6}'

   dart run tool/send_push.dart apns --sandbox ... --token <push token> \
     --event end --dismiss-after 10 \
     --content '{"title":"Order #1","body":"Delivered","progress":1}'
   ```

6. Tap the activity: the app opens and logs `tap: /orders/1`.

Tap handling alone can be checked on a simulator without APNs:

```bash
xcrun simctl openurl booted "liveupdates-com.ttechapp.liveUpdatesExample://tap?route=%2Forders%2F42"
```

### Troubleshooting

- `400 BadDeviceToken`: sandbox token sent to production or the other way round; check `--sandbox`.
- `400 TopicDisallowed` or `403`: the key, team or bundle id does not match.
- HTTP 200 but no change: check the device log (Console.app, process `LiveUpdatesWidget`) for `content-state` decoding errors; `title` is required.
- Apple throttles frequent updates. Add `NSSupportsLiveActivitiesFrequentUpdates` (the example has it) and use `--priority 5` for non-urgent updates.

## Android with FCM

### Prerequisites

- A Firebase project with an Android app for the example's application id
  (`com.ttechapp.live_updates_example`).
- In the example: `flutterfire configure` (or add `google-services.json`), add
  `firebase_core`, `firebase_messaging` and `live_updates_fcm`, then:

  ```dart
  @pragma('vm:entry-point')
  Future<void> _onBackgroundMessage(RemoteMessage message) async {
    await LiveUpdatesFcm.handleMessage(message);
  }

  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    LiveUpdatesFcm.listen();
    // Manual test only: printing tokens is fine on your own debug build, but
    // never log tokens in a production app (they allow pushing to the device).
    if (kDebugMode) {
      LiveUpdatesFcm.tokens().listen((t) => debugPrint('${t.type.name}: ${t.value}'));
    }
    await FirebaseMessaging.instance.register();
    runApp(const MaterialApp(home: ExamplePage()));
  }
  ```

- A service account key JSON with the *Firebase Cloud Messaging API Admin* role.

### Steps

1. Run the app, allow notifications and copy the `fcmInstallationId` from the log.
2. Start, update and end:

   ```bash
   cd packages/live_updates
   dart run tool/send_push.dart fcm --service-account sa.json --fid <installation ID> \
     --event start --id order-1 \
     --content '{"title":"Order #1","body":"Preparing","progress":0.1,"route":"/orders/1"}'

   dart run tool/send_push.dart fcm --service-account sa.json --fid <installation ID> \
     --event update --id order-1 --content '{"title":"Order #1","progress":0.6}'

   dart run tool/send_push.dart fcm --service-account sa.json --fid <installation ID> \
     --event end --id order-1
   ```

3. Repeat with the app in the background and after swiping it away: data
   messages with `android.priority: high` are handled by the background
   handler.
4. Check both rendering paths:
   - Android 16 QPR1 and later: the notification is promoted to a Live Update
     (status bar chip, top of the shade and Lock Screen) when
     `LiveUpdates.canPostPromotedNotifications()` is `true`. Users can turn
     promotion off per app in system settings. Android 16 builds without
     promoted notification support show `ProgressStyle` without the chip.
   - Android 15 or lower: a regular ongoing notification with a progress bar.
5. Tap the notification: the app logs `tap: /orders/1`.

## iOS through FCM

FCM can deliver Live Activity pushes when the app also uses FCM on iOS (APNs
key uploaded to Firebase). Send the Live Activity token (push or push-to-start)
together with the iPhone's Firebase Installation ID (`fcmInstallationId` from
`LiveUpdatesFcm.tokens()`):

```bash
dart run tool/send_push.dart fcm-ios --service-account sa.json \
  --fid <installation ID of the iPhone> --live-activity-token <hex> \
  --event update --content '{"title":"Order #1","progress":0.8}'
```
