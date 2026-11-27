import 'dart:io' show Platform;

import '../ios/bindings.g.dart' show LiveUpdatesBridge;
import '../models.dart';
import 'android_platform.dart';
import 'ios_platform.dart';
import 'live_updates_platform.dart';

/// Backend for the current native platform. Below iOS 16.2 (apps may target
/// iOS 15.0) the plugin does nothing, as on other platforms, except that
/// scheduling reports that it needs a newer iOS.
LiveUpdatesPlatform createDefaultPlatform() {
  if (Platform.isIOS) {
    return LiveUpdatesBridge.isAvailable()
        ? IosLiveUpdatesPlatform()
        : OldIosLiveUpdatesPlatform();
  }
  if (Platform.isAndroid) return AndroidLiveUpdatesPlatform();
  return NoopLiveUpdatesPlatform();
}

/// iOS versions without Live Activities: a no-op, but [schedule] and
/// [reschedule] throw like on iOS versions without scheduling, so apps
/// handle one case.
class OldIosLiveUpdatesPlatform extends NoopLiveUpdatesPlatform {
  static const _message = 'Scheduling live updates requires iOS 26 or later.';

  @override
  Future<void> schedule(
    String key,
    LiveUpdateContent content, {
    required DateTime at,
    bool pushUpdates = false,
    AndroidScheduleOptions android = const AndroidScheduleOptions(),
  }) async => throw const LiveUpdateException(
    _message,
    reason: LiveUpdateFailure.unsupported,
  );

  @override
  Future<void> reschedule(
    String key, {
    required DateTime at,
    LiveUpdateContent? content,
  }) async => throw const LiveUpdateException(
    _message,
    reason: LiveUpdateFailure.unsupported,
  );
}
