import 'dart:ui' show CallbackHandle, DartPluginRegistrant, PluginUtilities;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import 'models.dart';
import 'platform/live_updates_platform.dart';

/// Handles a button press while the app is not running (see
/// `LiveUpdates.setBackgroundActionHandler`).
typedef LiveUpdateActionHandler = Future<void> Function(
  LiveUpdateActionEvent event,
);

/// Registers [handler] for presses that arrive while no Dart listener of
/// `LiveUpdates.onAction` is active.
Future<void> registerBackgroundActionHandler(
  LiveUpdateActionHandler handler,
) async {
  final callback = PluginUtilities.getCallbackHandle(handler);
  if (callback == null) {
    throw ArgumentError.value(
      handler,
      'handler',
      'Must be a top-level or static function annotated with '
          "@pragma('vm:entry-point')",
    );
  }
  final dispatcher = PluginUtilities.getCallbackHandle(
    liveUpdatesBackgroundMain,
  )!;
  await LiveUpdatesPlatform.instance.setBackgroundActionHandler(
    dispatcher.toRawHandle(),
    callback.toRawHandle(),
  );
}

/// Entry point of the headless engine the plugin starts for background
/// button presses. Runs the registered handler for every queued press, then
/// tells the platform it is done so the engine can be shut down.
@pragma('vm:entry-point')
Future<void> liveUpdatesBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final platform = LiveUpdatesPlatform.instance;
  try {
    final raw = await platform.backgroundActionHandler();
    final handler = raw == null
        ? null
        : PluginUtilities.getCallbackFromHandle(
            CallbackHandle.fromRawHandle(raw),
          );
    if (handler is LiveUpdateActionHandler) {
      for (final (updateId, actionId) in await platform.takeQueuedActions()) {
        try {
          await handler(
            LiveUpdateActionEvent(updateId: updateId, actionId: actionId),
          );
        } on Object catch (error) {
          debugPrint('live_updates: background action handler failed: $error');
        }
      }
    }
  } finally {
    await platform.backgroundActionsDone();
  }
}
