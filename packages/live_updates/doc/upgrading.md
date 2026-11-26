# Upgrading live_updates

What to change when you move to a new version. Breaking changes come
with a new minor version. After every update, also follow
[Upgrading](../README.md#upgrading) in the README (run
`dart run live_updates:create ios` again). If you skip versions,
apply each section from your current version upward, oldest first.

## From 0.4.x to 0.5.0

- **`create_widget` is now `create ios`:** replace
  `dart run live_updates:create_widget` with
  `dart run live_updates:create ios`. The options and the behavior are the
  same, and your layout file and other edited files are kept.
  `dart run live_updates:create` with no platform sets up every platform
  the app has, including the optional
  [Android custom layouts](../README.md#customizing-the-android-notification); use
  `create ios` if you only need the widget.
- **`extra` and `extraImages` moved to `LiveUpdateContent`:** move them
  from `IosLiveUpdateOptions` to
  `LiveUpdateContent(extra: ..., extraImages: ...)`. The old fields are
  deprecated. They still work on iOS (merged with the new ones; the iOS
  value wins for the same key), but Android custom layouts read only the
  new fields. The keys in the iOS content state and in push payloads are
  unchanged.

## From 0.3.x to 0.4.0

- **Android keeps an ended update for up to 4 hours by default**, as iOS
  does: `end()` without `finalContent` no longer removes the notification at
  once but leaves the content shown last as a regular notification, and
  `dismissAfter: null` (also a remote `end` without
  `live_updates_dismiss_after`) means 4 hours instead of "until dismissed".
  To remove it at once as before, pass `dismissAfter: Duration.zero` (remote:
  `"live_updates_dismiss_after": 0`). `endAll()` removes these too.
- **Android `start`, `startOrUpdate` and `update` throw a
  `LiveUpdateException`** while notifications are turned off for the app or
  its channel, as on iOS (`schedule` and `reschedule` too, for a time that
  has passed). Before, they returned as if the update were
  shown. Check `isSupported()` first, or catch the exception.
- **Android removes a notification when its countdown ends** (a
  notification's countdown cannot stop at zero), and leaves out the timer of
  a countdown that is already over. Pass
  `AndroidLiveUpdateOptions(removeAtCountdownEnd: false)` to keep it.
- **iOS 16.2 and later:** Live Activities now work from iOS 16.2. Run
  `create ios` again, then lower the deployment target of the
  `LiveUpdatesWidget` target to 16.2 in Xcode and check that your layout file
  builds for it (`create ios` does not change an existing target, and
  says when it is higher; with `--no-xcode` check it yourself).
  `create ios` also adds `LiveUpdatesWidget` = YES to the widget's
  `Info.plist`, so the plugin checks that extension: until it supports the
  device's iOS, `isSupported()` stays `false` there, so the app does not
  start activities that no widget can show. Without the key, any widget
  extension of the app that supports the device's iOS counts: on iOS 16.2
  to 17.1, `isSupported()` can then return `true` while the Live Activity
  extension still targets 17.2 (as in 0.3.x), and activities may start
  without being shown. If you set up the extension by hand, add the key
  yourself (see [Manual setup](../README.md#manual-setup)).
- **What stays after `end` has no buttons or running timers** on either
  platform (the final content, or the content shown last).
- **iOS `startOrUpdate` replaces an ended activity** with the key that is
  still on the Lock Screen, instead of doing nothing; only an activity the
  user dismissed still keeps the key from starting.
- **Android remote `alert`:** an `alert` object in `live_updates_content`
  now alerts. Send `"androidAlert": false` to keep such an update silent.

## From 0.2.x to 0.3.0

- **Android live updates are removed after 8 hours by default**
  (`AndroidLiveUpdateOptions.maxDuration`), as iOS ends Live Activities after
  at most 8 hours. To keep the old behavior, pass
  `AndroidLiveUpdateOptions(maxDuration: null)`; remote payloads send
  `"maxDurationMillis": 0`.
- Run `create ios` again (and update your layout file as described in
  [Upgrading](../README.md#upgrading)) to show
  `endedContent` on iOS.

## From 0.1.x to 0.2.0

Icons are now `LiveUpdateIcon` values (see [Icons](../README.md#icons)):

| 0.1.x | 0.2.0 |
| --- | --- |
| `iconName: 'ic_stat'` | `icon: LiveUpdateIcon.native('ic_stat')` |
| `progressTrackerIcon: 'ic_car'` | `progressTrackerIcon: LiveUpdateIcon.native('ic_car')` |
| `LiveUpdateAction(iosSystemImage: 'xmark')` | `LiveUpdateAction(icon: LiveUpdateIcon.symbol('xmark'))` |
| `LiveUpdateAction(androidIcon: 'ic_close')` | `LiveUpdateAction(androidIcon: LiveUpdateIcon.native('ic_close'))` |

In remote payloads, `"iconName": "ic_stat"` becomes
`"icon": {"native": "ic_stat"}`, and so on for `progressTrackerIcon` and the
button keys (`systemImage` becomes `"icon": {"symbol": ...}`). Run
`create ios` again so the widget reads the new keys and gets its asset
catalog. On iOS, activities started before the upgrade show the default
icon until their next update.
