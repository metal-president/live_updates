# Releasing

Every release of `live_updates` and `live_updates_fcm` follows these steps.

1. **Security review ×3.** Three independent reviews of the changes since the
   last release (for example: a full read-through; supply chain, build files
   and published contents; runtime data flow and untrusted input). Look for
   malicious or unexpected code, secrets, and security weaknesses. Fix every
   finding before continuing.
2. **Accuracy review.** Check code, comments and documentation (README,
   CHANGELOG, `docs/`, dartdoc, templates) for mistakes and outdated
   information, verified against the official Apple, Android, Firebase and
   Flutter documentation. If a new OS or SDK has been released since the last
   release (iOS / Xcode, Android / API level, Flutter / Dart,
   firebase_messaging, FFIgen / JNIgen), review what changed and update code
   and docs for it (new or deprecated APIs, changed behavior, version
   requirements).
3. **Pull request.** Bump versions and changelogs, open a PR and wait for all
   CI jobs (`analyze-test`, `build-android`, `build-ios (swiftpm)`,
   `build-ios (cocoapods)`) to pass, then squash-merge.
4. **Publish** from a clean, up-to-date `main`: `dart pub publish --dry-run`
   (0 warnings), then `dart pub publish` for `live_updates` first and
   `live_updates_fcm` after the new core version is visible on pub.dev.
5. **Tag** each package: `live_updates-vX.Y.Z`, `live_updates_fcm-vX.Y.Z`.
