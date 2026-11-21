# live_updates

iOS **Live Activities** and Android **Live Update** notifications with one Dart API.

- One API to start, update and end a live update: title, body, progress, icon and a tap route.
- iOS 17.2+: ActivityKit Live Activities on the Lock Screen and in the Dynamic Island, with a ready-made SwiftUI widget you generate and customize.
- Android: ongoing notifications that Android 16 renders with `ProgressStyle` and, on builds that support promoted notifications (Android 16 QPR1 and later), promotes to Live Updates with a status bar chip. Older Android versions show a regular ongoing notification with a progress bar.
- Remote updates: iOS push-to-start and per-activity push tokens as streams; Android updates from a received payload (FCM glue lives in [`live_updates_fcm`](https://pub.dev/packages/live_updates_fcm)).
- No platform channels: native code is called through [FFIgen](https://pub.dev/packages/ffigen) (iOS) and [JNIgen](https://pub.dev/packages/jnigen) (Android). No third-party dependencies beyond the official `objective_c` and `jni` interop runtimes.
- Other platforms are a safe no-op.

> **Status:** 0.x. The API may still change between minor versions.

## Platform support

| | iOS | Android 16+ | Android 7–15 | Other |
| --- | --- | --- | --- | --- |
| Start / update / end | Live Activity | Live Update (when promoted) | Ongoing notification | no-op |
| Progress | ✓ | `ProgressStyle` | progress bar | |
| Tap route | ✓ | ✓ | ✓ | |
| Lifecycle events | ✓ | ✓ | ✓ | |
| Push tokens | ✓ | – | – | |
| Remote payload | APNs (direct) | `handleRemotePayload` | `handleRemotePayload` | |

Requirements: Flutter 3.50+, iOS 17.2+, Android minSdk as set by Flutter.

## Getting started

```bash
flutter pub add live_updates
```

### iOS

1. Generate the widget extension from your app's root directory:

   ```bash
   dart run live_updates:create_widget
   ```

   This writes `ios/LiveUpdatesWidget/`, adds a *LiveUpdatesWidget* extension
   target to `Runner.xcodeproj` (using the `xcodeproj` Ruby gem that ships with
   CocoaPods), sets `NSSupportsLiveActivities` and registers the
   `liveupdates-<bundle id>` URL scheme used for taps. Use `--no-xcode` to only
   write the files and add the target yourself (File > New > Target > Widget
   Extension, deployment target 17.2).

2. Open the project in Xcode once and select a signing team for the new target.

3. For push updates, add the **Push Notifications** capability to the Runner
   target.

The UI lives in `ios/LiveUpdatesWidget/LiveUpdatesWidgetLiveActivity.swift`;
edit it freely. Keep `LiveUpdatesAttributes.swift` identical to the plugin's
copy, because ActivityKit matches the two by name and shape.

### Android

Nothing to configure. The plugin declares `POST_NOTIFICATIONS` and
`POST_PROMOTED_NOTIFICATIONS`. Call `LiveUpdates.requestPermission()` before
starting on Android 13+.

Android only promotes a notification to a Live Update when the build supports
it, the user allows it (`LiveUpdates.canPostPromotedNotifications()`), and the
notification meets the system's criteria. Otherwise it stays a regular
ongoing notification.

## Platform guidelines

Both platforms limit what these surfaces are for. Follow Apple's Human
Interface Guidelines for Live Activities and Android's
[Live Update guidance](https://developer.android.com/develop/ui/views/notifications/live-update):

- Use them for ongoing, user-initiated, time-sensitive activities, such as a
  ride, a food order, navigation, a call or a sports score.
- Do not use them for ads, promotions, chat messages or reminders.
- Do not start them for something the user did not ask for. On Android set
  `AndroidLiveUpdateOptions(requestPromotion: false)` for anything that is not
  a Live Update; it then stays a regular notification.
- Do not bring back an update the user dismissed. On Android `update` fails
  for a dismissed update, and remote `update` payloads for it are ignored.
- Keep `shortCriticalText` short (Android suggests at most 7 characters).

## Usage

```dart
import 'package:live_updates/live_updates.dart';

if (await LiveUpdates.requestPermission()) {
  final update = await LiveUpdates.start(
    const LiveUpdateContent(
      title: 'Order #1234',
      body: 'Preparing',
      progress: 0.1,
      route: '/orders/1234',
      android: AndroidLiveUpdateOptions(shortCriticalText: '10 min'),
    ),
  );

  await update.update(
    const LiveUpdateContent(title: 'Order #1234', body: 'On the way', progress: 0.6),
  );

  await update.end(dismissAfter: const Duration(minutes: 5));
}

// Taps on a live update deliver its route. Only routes that one of the
// app's live updates carries are delivered, but treat them like any deep
// link: validate before acting on them.
LiveUpdates.onTap.listen((route) => router.go(route));

// Live updates still running, e.g. after an app restart.
final running = await LiveUpdates.active();

// Live updates that appear while the app runs, including remote starts.
LiveUpdates.onStarted.listen((update) => track(update));

// Lifecycle: stale (iOS), ended, dismissed (e.g. swiped away on Android).
update.states.listen((state) => print(state));

await LiveUpdates.endAll();
```

### One live update per key

When your data already has an id, use it as the key. Calling
`startOrUpdate` again updates the same live update instead of starting a
duplicate, and `find` gets it back after an app restart:

```dart
await LiveUpdates.startOrUpdate('order-1234', content);
final update = await LiveUpdates.find('order-1234');
```

On Android the key is the update's id and is the same as `live_updates_id`
in remote payloads, so the app and the server address the same notification.
On iOS the key is stored in the activity's attributes; a push-to-start can set
it with `"attributes": {"key": "order-1234"}`.

### Buttons

```dart
const LiveUpdateContent(
  title: 'Order #1234',
  actions: [
    LiveUpdateAction(id: 'cancel', title: 'Cancel', iosSystemImage: 'xmark'),
    LiveUpdateAction(id: 'track', title: 'Track', opensApp: true),
  ],
);

LiveUpdates.onAction.listen((event) {
  // event.updateId, event.actionId
});
```

- Buttons without `opensApp` run in the background: on iOS through
  `LiveUpdatesActionIntent` (a `LiveActivityIntent` that `create_widget`
  compiles into both the app and the widget), on Android through a broadcast
  receiver. The press is delivered to `onAction` while the app runs. If the
  app was not running, it is queued and delivered once Dart listens; use
  `opensApp: true` when the press must be handled right away.
- `opensApp: true` opens the app and delivers the press.
- Android shows up to three actions. On iOS keep labels short: the whole
  content must stay under ActivityKit's 4 KB limit.

### Images

Pass a picture with the content. It becomes the thumbnail in the iOS widget
template (Lock Screen and Dynamic Island) and the large icon of the Android
notification:

```dart
const LiveUpdateContent(
  title: 'Courier on the way',
  image: LiveUpdateImage.asset('assets/courier.png'),
  // or LiveUpdateImage.file(path), .memory(bytes), .network(Uri.parse(url))
);
```

Images are scaled to `maxDimension` pixels (default 256), stored as PNG and
reused when identical; files unused for a day are cleaned up.

On iOS the widget extension cannot read the app's files, so images go through
an App Group. `create_widget` sets one up by default (`group.<app bundle id>`,
or `--app-group <id>`): it adds the entitlement to both targets and writes the
`LiveUpdatesAppGroup` Info.plist key the plugin and the widget read. With
automatic signing Xcode registers the group; otherwise add it in your Apple
Developer account. A customized widget loads an image with
`LiveUpdatesImages.url(context.state.image)`.

### Icons

`iconName` names a drawable (or mipmap) on Android and an image in the widget
extension's asset catalog on iOS. Without it, the app icon (Android) or a
system symbol (iOS widget template) is used.

## Remote updates

### iOS (APNs)

```dart
// Start activities from your server (iOS 17.2+).
LiveUpdates.pushToStartTokens.listen((token) => api.registerPushToStart(token.hex));

// Update a running activity from your server.
final update = await LiveUpdates.start(
  const LiveUpdateContent(title: 'Order #1234'),
  pushUpdates: true,
);
update.pushTokens.listen((token) => api.registerActivity(update.id, token.hex));
```

Send pushes with `apns-push-type: liveactivity` and topic
`<bundle id>.push-type.liveactivity`. The `content-state` uses the same keys as
`LiveUpdateContent`: `title`, `body`, `progress`, `iconName`, `route`, `extra`.
For push-to-start, set `"attributes-type": "LiveUpdatesAttributes"` and
`"attributes": {}`.

### Android

Deliver a data message and pass it to `LiveUpdates.handleRemotePayload`:

| Key | Value |
| --- | --- |
| `live_updates_event` | `start`, `update` or `end` |
| `live_updates_id` | Your id for the update (used by later messages) |
| `live_updates_content` | Content as a JSON string, same keys as above |
| `live_updates_dismiss_after` | Optional, seconds to keep final content on `end` |

With Firebase, [`live_updates_fcm`](https://pub.dev/packages/live_updates_fcm)
does this for you.

See [docs/testing-remote.md](https://github.com/metal-president/live_updates/blob/main/docs/testing-remote.md)
for a step-by-step verification guide and `tool/send_push.dart` for a sender.

## How it works

- **iOS:** a small `@objc` Swift class (`LiveUpdatesBridge`) wraps ActivityKit
  for one fixed `ActivityAttributes` type, `LiveUpdatesAttributes`. Dart calls
  it through FFIgen-generated Objective-C bindings.
- **Android:** a Java class (`LiveUpdatesBridge`) builds the notifications.
  Dart calls it through JNIgen-generated bindings.

## License

MIT
