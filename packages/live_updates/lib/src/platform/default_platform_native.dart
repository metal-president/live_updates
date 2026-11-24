import 'dart:io' show Platform;

import '../ios/bindings.g.dart' show LiveUpdatesBridge;
import 'android_platform.dart';
import 'ios_platform.dart';
import 'live_updates_platform.dart';

/// Backend for the current native platform. Below iOS 17.2 (apps may target
/// iOS 15.0) the plugin does nothing, as on other platforms.
LiveUpdatesPlatform createDefaultPlatform() {
  if (Platform.isIOS) {
    return LiveUpdatesBridge.isAvailable()
        ? IosLiveUpdatesPlatform()
        : NoopLiveUpdatesPlatform();
  }
  if (Platform.isAndroid) return AndroidLiveUpdatesPlatform();
  return NoopLiveUpdatesPlatform();
}
