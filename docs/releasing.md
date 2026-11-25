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
3. **README review.** Read the README of each package as a new user would:
   - Is it clear what the package is for, what it can do and when to use it?
   - Can a new user follow the setup and the first example without missing
     steps, prerequisites, dependencies or imports?
   - Is the text easy to read: short sentences, no repeated notes, details
     after the basics?

   CI compiles the Dart examples of both READMEs
   (`tool/check_readme_snippets.dart`); this review covers what it cannot.
4. **Minimum iOS check.** CI only runs the newest iOS simulator. Run the
   example app on an iOS 16 simulator (for example iOS 16.4): Start /
   Update / End must work, buttons that run an intent are left out (only
   `opensApp` buttons show) and push-to-start reports no token. Below iOS
   16.2 (when a simulator is available) the app must launch, show
   `supported: false`, and Start / Update / End must not crash.
5. **Pull request.** Bump versions and changelogs, open a PR and wait for all
   CI jobs (`analyze-test`, `android-unit-test`, `ios-unit-test`,
   `build-android`, `build-ios (swiftpm)`, `build-ios (cocoapods)` and the
   integration tests) to pass, then squash-merge.
6. **Publish** from a clean, up-to-date `main`: `dart pub publish --dry-run`
   (0 warnings), then `dart pub publish` for `live_updates` first and
   `live_updates_fcm` after the new core version is visible on pub.dev.
7. **Tag** each package: `live_updates-vX.Y.Z`, `live_updates_fcm-vX.Y.Z`.
