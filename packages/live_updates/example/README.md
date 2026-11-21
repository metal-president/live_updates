# live_updates example

Starts, updates and ends a live update, shows push tokens and tap routes.

```bash
fvm flutter run
```

- iOS: the `LiveUpdatesWidget` extension was generated with
  `dart run live_updates:create_widget`. Select a signing team for both
  targets to run on a device. Enable the Push Notifications capability before
  turning on "Request push token".
- Android: run the integration test with `tool/integration_test_android.sh`,
  which grants the notification permission automatically.

See `docs/testing-remote.md` in the repository for push testing.
