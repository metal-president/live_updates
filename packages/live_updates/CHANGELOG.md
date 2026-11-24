## 0.2.1

- `LiveUpdateContent.publicContent` (`LiveUpdatePublicContent`): content shown
  on the Lock Screen while the system hides sensitive content, which depends
  on the person's settings. It keeps the icon, colors and tap route and, unless
  `keepProgress` / `keepTimer` is false, the progress and timer; images,
  buttons, metrics, steps, the journey and `extra` are left out.
  - Android: the notification's public version (`setPublicVersion`).
  - iOS: the generated widget's building blocks show it when the widget sees
    the `privacy` or `placeholder` redaction reason. New building blocks
    `LiveUpdatesPublicLockScreen` (for layouts of your own, with
    `state.liveUpdatesShowsPublic(redactionReasons)`) and
    `LiveUpdatesExpandedCenter` (the expanded Dynamic Island title). Run
    `dart run live_updates:create_widget` again; a layout file generated
    before should use `LiveUpdatesExpandedCenter` in its expanded center
    region (see Upgrading in the README).
- `AndroidLiveUpdateOptions.lockScreenVisibility`:
  `AndroidLockScreenVisibility.private` (default, now set explicitly) or
  `secret`, which hides the notification on a secure lock screen.
- Remote payloads: `publicContent` (`title`, `body`, `keepProgress`,
  `keepTimer`) and `"androidLockScreenVisibility": "secret"`.

## 0.2.0

Breaking: icons are `LiveUpdateIcon` values. See "From 0.1.x to 0.2.0" in
the README, and run `dart run live_updates:create_widget` again.

- `LiveUpdateIcon`: a native resource (`.native`, an Android drawable or an
  image in the widget extension's asset catalog), a Flutter asset (`.asset`)
  or an SF Symbols name (`.symbol`, iOS only).
- `LiveUpdateContent.icon` replaces `iconName`. New per-platform icons:
  `AndroidLiveUpdateOptions.smallIcon`, `IosLiveUpdateOptions.icon` and
  `IosLiveUpdateOptions.islandIcon` (the Dynamic Island, so a photo `image`
  can stay on the Lock Screen). `AndroidLiveUpdateOptions.progressTrackerIcon`
  is a `LiveUpdateIcon`.
- `LiveUpdateAction.icon`, `iosIcon` and `androidIcon` (all `LiveUpdateIcon`)
  replace `iosSystemImage` and the drawable name `androidIcon`.
- Each place uses the first icon that is set, and an icon that cannot be
  shown falls back to the platform default (not to the next icon) with a
  warning in the log. Debug builds also print obvious mistakes in Dart.
- Android: a default icon for updates without one (including remote ones)
  through the `com.ttechapp.live_updates.default_icon` manifest meta-data.
  Flutter assets are read from the app package, also for remote updates.
- iOS: `LiveUpdates.preloadIcons` stores asset icons (single assets or whole
  folders) for content sent by a push. `create_widget` adds an asset catalog
  to the widget extension.
- iOS: `IosLiveUpdateOptions.compactLeading` chooses the leading side of the
  compact Dynamic Island, like `compactTrailing` and `minimal`.
- Remote payloads: icons are objects (`{"native": ...}`, `{"asset": ...}` or
  `{"symbol": ...}`) under `icon`, `iosIcon`, `islandIcon`,
  `androidSmallIcon` and `progressTrackerIcon`; `iconName` and the action key
  `systemImage` are no longer read.
- Docs: README Icons section with the official size and color guidance of
  both platforms, keeping drawables in release builds, and the remote icon
  keys in docs/server-fcm.md.

## 0.1.3

- iOS: apps can target iOS 15.0 (was 17.2). Below iOS 17.2 every call does
  nothing, as on other platforms, and `LiveUpdates.isSupported()` returns
  `false`. The widget extension still targets iOS 17.2. If your app targets
  iOS 16 or earlier, run `dart run live_updates:create_widget` again to update
  `LiveUpdatesActionIntent.swift`.
- Android: unit tests on Android 7.0, 8.0, 13 and 15 for the regular
  notification fallback, and an Android Lint check (`NewApi`) in CI.

## 0.1.2

- Docs: README adds a Platform limits section (Live Activity duration, 4 KB
  size limit, Lock Screen height, user settings, number of activities, push
  budget and frequent updates, where Live Activities appear; Android
  promotion criteria, user settings, status bar chip, notification
  permission), each with a link to the official documentation.
- Docs: in the buttons table, an `opensApp` press opens the app only when it
  is in the background.
- Docs: removed the unsourced guideline to keep metric labels to 10
  characters.
- Package topics: `dynamic-island` replaces `widget`.

## 0.1.1

- Android: in a regular notification (`AndroidLiveUpdateMode.classic`, and
  Android 15 and earlier) with a body, the steps, journey and metrics text is
  a second line of the expanded notification instead of being cut off in the
  header.
- Docs: screenshots of each layout on iOS and Android. In tests on iOS 27
  (device and simulator) the default Lock Screen card was black in Light and
  Dark Mode; 0.1.0 said white in Light Mode, as Apple's guidelines describe
  for Light Mode (which other versions or setups may still show).
- Docs: README reorganized (shorter getting started, a table of where button
  presses go, one Upgrading section) and the first usage example fixed;
  accuracy fixes (Android 17 metrics in `classic`, imports in examples).

## 0.1.0

Breaking changes (from now on they come only with a new minor version):

- `AndroidMetric` is renamed to `LiveUpdateMetric` (`AndroidMetricKind` to
  `LiveUpdateMetricKind`), and `metrics` / `criticalMetric` move from
  `AndroidLiveUpdateOptions` to `LiveUpdateContent`. The content-state keys
  are unchanged.
- `AndroidLiveUpdateOptions.requestPromotion` is replaced by `mode`
  (`AndroidLiveUpdateMode.liveUpdate`, `ongoing`, `classic`).
  `requestPromotion: false` becomes `mode: AndroidLiveUpdateMode.ongoing`;
  `classic` shows the same notification as Android 15 and earlier on every
  version. Remote payloads with `requestPromotion: false` still work.
- Button presses reach the app's Dart listeners only while the app is in the
  foreground; otherwise the background handler runs them, so the system
  keeps the app alive for them. `LiveUpdates.onAction` takes every press,
  `LiveUpdate.actions` only that update's; other presses stay queued and run
  the background handler, also while the app is open. An open-app press that
  no listener takes within 5 seconds runs the background handler.
- Platform interface: `LiveUpdatesPlatform.actions` is now
  `actions({String? updateId})`.

New:

- Layouts: `IosLiveUpdateOptions.layout` (`IosLiveUpdateLayout.standard`,
  `timer`, `metrics`, `stepper`, `journey`, or `custom('name')` for a layout
  of your own) chooses the Lock Screen and expanded Dynamic Island pattern of
  the generated widget. New shared data `LiveUpdateContent.steps`
  (`LiveUpdateSteps`) and `journey` (`LiveUpdateJourney`). Android uses the
  same data: steps become progress segments and points on Android 16+, and
  steps, journey and number and text metrics are added to the notification
  text where the system does not show them otherwise.
- `IosLiveUpdateOptions.color`, `backgroundColor` and `foregroundColor`:
  accent, Lock Screen background and text of the generated widget
  (content-state keys `tintArgb` / `backgroundArgb` / `foregroundArgb`); the
  Always-On display uses system colors.
- Run `dart run live_updates:create_widget` after updating to refresh
  `LiveUpdatesViews.swift`, `LiveUpdatesAttributes.swift` and
  `LiveUpdatesActionIntent.swift`; the generated layout file now switches on
  `context.state.layout` for custom layouts (add the switch to an older
  layout file, or regenerate it with `--force`).

Fixes:

- Background handler: a press that arrives as a run finishes is run; a
  handler that can no longer be found drops the queued presses instead of
  starting engines repeatedly.
- Taps and lifecycle events reach every engine that listens (a background
  engine no longer takes them from the app), and listeners of a destroyed
  engine are dropped.
- Android: a tap no longer passes the plugin's internal URI to Flutter as a
  deep link; an update removed by `timeoutAfter` is not treated as dismissed
  by the user (it reports `ended`, and its key can be started again); a
  remote or local `end` never brings back a dismissed update, and a remote
  `end` keeps final content when `live_updates_dismiss_after` is missing;
  concurrent `requestPermission` calls all complete; `update` no longer
  throws when the user turned the channel off; reopening from Recents does
  not deliver a tap again.
- iOS: a tap that launches an app without scenes is delivered once; taps
  keep working when the background handler started first; `active()` leaves
  out ended activities, `update` on an ended one throws, `startOrUpdate`
  prefers the running activity with the key, and `states` reports
  `dismissed` after `ended`.
- A non-finite `progress` is left out instead of breaking the content.
- Network images: redirects must stay on https; image files are written
  atomically; `maxDimension` must be positive.
- `create_widget` reports a missing option value.

## 0.0.6

- Docs: clearer platform table (Live Activity push tokens, buttons, images,
  remote updates, broadcasts), requirements, `end(dismissAfter:)` on Android,
  and complete push-to-start keys.

## 0.0.5

- `LiveUpdate.key`: the key from `startOrUpdate`, a push-to-start
  `attributes.key` (iOS) or a remote `live_updates_id` (Android), also on
  updates from `active()` and `onStarted`.
- Docs: sending to both platforms through FCM (`docs/server-fcm.md`).
- `IosLiveUpdateOptions.compactTrailing` and `minimal` (`IosIslandContent`):
  choose what the compact and minimal Dynamic Island show.
- `create_widget`: the reusable views move to `LiveUpdatesViews.swift`, which
  `create_widget` always updates together with `LiveUpdatesAttributes.swift`
  and `LiveUpdatesActionIntent.swift`. Your layout file is kept unless you pass
  `--force`. Existing layouts keep working; run `create_widget --force` once
  to switch to the shorter layout that uses the shared views (needed for
  `compactTrailing` / `minimal`). `LiveUpdatesActionIntent.swift` is now
  always replaced; a file without the generated header is kept as `.bak`.
- Screenshots on pub.dev and in the README; the example app has its own icon.

## 0.0.4

- `LiveUpdateContent.timer`: a countdown or stopwatch counted by the system
  (iOS widget template, Android chronometer). Re-run
  `create_widget --force` to update the widget.
- Android: `progressSegments`, `progressPoints` and `progressTrackerIcon`
  (Android 16+ `ProgressStyle`), `timeoutAfter` and `alert`.
- Docs: Android 17 does not show the body text of a Live Update with
  `metrics`.

## 0.0.3

- iOS 18 broadcast: `start(..., iosChannelId:)` and `startOrUpdate(...,
  iosChannelId:)` subscribe a Live Activity to an APNs broadcast channel.
- `tool/send_push.dart`: `apns-channel` (create, list, delete) and
  `apns-broadcast` commands; `--input-push-channel` and `--activity-key` for
  push-to-start.
- `create_widget`: per-configuration widget bundle ids and App Groups for
  flavors (`LIVE_UPDATES_APP_GROUP` build setting); offers to install the
  xcodeproj gem when it is missing; manual setup steps in the README.
- `LiveUpdates.setBackgroundActionHandler`: handle button presses while the
  app is not running in a headless Flutter engine (Android and iOS).
  Re-run `create_widget --force` to update `LiveUpdatesActionIntent.swift`.
- `LiveUpdateAction.requiresUnlock`: ask for an unlock before a Lock Screen
  press is handled (iOS, Android 12+).
- Android 17: `AndroidLiveUpdateOptions.metrics` (`MetricStyle`, with
  `criticalMetric`) and semantic colors for the body, the progress bar and
  metrics (`LiveUpdateSemanticStyle`).
- iOS 27: the generated widget leaves the title out of the compact Dynamic
  Island view when it is limited in width (landscape). Re-run
  `create_widget --force` to update the widget.
- Fix: an Android `channelId` option no longer affects iOS push settings.

## 0.0.2

- Push tokens (`LiveUpdate.pushTokens`, `LiveUpdates.pushToStartTokens`)
  replay the current token to new listeners.
- `LiveUpdatePushToken.toString()` no longer includes the token.

## 0.0.1

- Initial release.
- Start, update and end iOS Live Activities and Android Live Updates with one API.
- iOS: FFIgen bindings to an ActivityKit bridge, push-to-start and push token
  streams, `create_widget` command generating a SwiftUI widget extension.
- Android: JNIgen bindings; ongoing notifications with `ProgressStyle` on
  Android 16+ and promotion to Live Updates where supported, progress bar
  fallback below; remote payloads; `canPostPromotedNotifications()`.
- Tap routes, notification permission request, no-op on other platforms.
- Images (`LiveUpdateImage`) shared with the iOS widget through an App Group
  and shown as the Android large icon.
- `endAll()`, `onStarted` and `LiveUpdate.states`.
- `startOrUpdate(key, content)` and `find(key)` for app-chosen keys.
- Buttons (`LiveUpdateAction`) with background or open-app handling and
  `onAction` / `LiveUpdate.actions`.
