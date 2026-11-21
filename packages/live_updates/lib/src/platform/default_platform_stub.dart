import 'live_updates_platform.dart';

/// Backend for platforms without dart:ffi (the web).
LiveUpdatesPlatform createDefaultPlatform() => NoopLiveUpdatesPlatform();
