# live_updates example

Starts, updates and ends a live update, shows push tokens and tap routes.

```bash
fvm flutter run
```

- iOS: the `LiveUpdatesWidget` extension was generated with
  `dart run live_updates:create ios`. Select a signing team for both
  targets to run on a device. Enable the Push Notifications capability before
  turning on "Request push token".
- Android: "Custom layout (Android)" shows the order with the layouts in
  `android/app/src/main/res/layout/live_update_custom*.xml`, generated with
  `dart run live_updates:create android`.
- Android: run the integration test with `tool/integration_test_android.sh`,
  which grants the notification permission automatically. The plugin's JVM
  unit tests (Robolectric, Java 21) run with
  `./gradlew :live_updates:testDebugUnitTest` from `android/`.

See `docs/testing-remote.md` in the repository for push testing.
