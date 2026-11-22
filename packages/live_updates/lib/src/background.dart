import 'dart:ui' show CallbackHandle, DartPluginRegistrant, PluginUtilities;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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
  await runBackgroundActions(
    LiveUpdatesPlatform.instance,
    (raw) => PluginUtilities.getCallbackFromHandle(
      CallbackHandle.fromRawHandle(raw),
    ),
  );
}

/// Runs the handler that [resolve] finds for the stored handle on every
/// queued press, until the queue is empty, then reports done.
///
/// Without a handler (removed from the app, or not an entry point) the
/// queued presses are dropped: otherwise the platform would start an engine
/// for them again and again.
@visibleForTesting
Future<void> runBackgroundActions(
  LiveUpdatesPlatform platform,
  Function? Function(int raw) resolve,
) async {
  try {
    final raw = await platform.backgroundActionHandler();
    final handler = raw == null ? null : resolve(raw);
    if (handler is! LiveUpdateActionHandler) {
      final dropped = await platform.takeQueuedActions();
      debugPrint(
        'live_updates: no background action handler; '
        'dropped ${dropped.length} press(es)',
      );
      return;
    }
    // Presses that arrive while the handler runs are queued too: keep
    // draining until the queue is empty.
    for (
      var queued = await platform.takeQueuedActions();
      queued.isNotEmpty;
      queued = await platform.takeQueuedActions()
    ) {
      for (final (updateId, actionId) in queued) {
        try {
          await handler(
            LiveUpdateActionEvent(updateId: updateId, actionId: actionId),
          );
        } on Object catch (error) {
          debugPrint('live_updates: background action handler failed: $error');
        }
      }
    }
  } on Object catch (error) {
    debugPrint('live_updates: background actions failed: $error');
  } finally {
    await platform.backgroundActionsDone();
  }
}
