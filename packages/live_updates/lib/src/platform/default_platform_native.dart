import 'dart:io' show Platform;

import 'android_platform.dart';
import 'ios_platform.dart';
import 'live_updates_platform.dart';

/// Backend for the current native platform.
LiveUpdatesPlatform createDefaultPlatform() {
  if (Platform.isIOS) return IosLiveUpdatesPlatform();
  if (Platform.isAndroid) return AndroidLiveUpdatesPlatform();
  return NoopLiveUpdatesPlatform();
}
