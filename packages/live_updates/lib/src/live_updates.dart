import 'background.dart';
import 'models.dart';
import 'platform/live_updates_platform.dart';

/// A running live update.
final class LiveUpdate {
  LiveUpdate._(this.id, [this.key]);

  /// Platform identifier (ActivityKit activity id or notification id).
  final String id;

  /// The key given to [LiveUpdates.startOrUpdate], or set by the server when
  /// it started the update (push-to-start `attributes.key` on iOS,
  /// `live_updates_id` on Android). `null` for [LiveUpdates.start].
  ///
  /// Send it to your server with the update's push tokens so the server can
  /// address the update by your own id on both platforms. Keys appear in
  /// notification data and push payloads: do not put secrets in them.
  final String? key;

  LiveUpdatesPlatform get _platform => LiveUpdatesPlatform.instance;

  /// Replaces the shown content.
  Future<void> update(LiveUpdateContent content) =>
      _platform.update(id, content);

  /// Ends the update. On iOS [dismissAfter] keeps it on the Lock Screen for
  /// that long; `Duration.zero` removes it immediately.
  Future<void> end({LiveUpdateContent? finalContent, Duration? dismissAfter}) =>
      _platform.end(id, finalContent: finalContent, dismissAfter: dismissAfter);

  /// Lifecycle changes of this live update, such as the user dismissing it
  /// (Android) or the system marking it stale (iOS).
  Stream<LiveUpdateState> get states => _platform.events
      .where((e) => e.$1 == id)
      .map((e) => _stateFromName(e.$2))
      .where((s) => s != null)
      .cast<LiveUpdateState>();

  /// Presses of this update's buttons ([LiveUpdateContent.actions]).
  Stream<String> get actions =>
      _platform.actions.where((e) => e.$1 == id).map((e) => e.$2);

  /// Per-activity APNs push tokens (iOS only, empty elsewhere). A new
  /// listener first receives the current token, if one is known. Requires
  /// starting with `pushUpdates: true`.
  Stream<LiveUpdatePushToken> get pushTokens => _platform.pushTokens(id);

  @override
  bool operator ==(Object other) => other is LiveUpdate && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  // The key may be your own id, such as an order number: keep it out of logs.
  String toString() => 'LiveUpdate($id)';
}

LiveUpdateState? _stateFromName(String name) => switch (name) {
  'active' => LiveUpdateState.active,
  'stale' => LiveUpdateState.stale,
  'ended' => LiveUpdateState.ended,
  'dismissed' => LiveUpdateState.dismissed,
  _ => null,
};

/// Entry point of the plugin.
abstract final class LiveUpdates {
  static LiveUpdatesPlatform get _platform => LiveUpdatesPlatform.instance;

  /// Whether live updates can be shown on this device right now. Always
  /// `false` on platforms other than iOS and Android.
  static Future<bool> isSupported() => _platform.isSupported();

  /// Asks for the permission needed to show live updates and returns whether
  /// they can be shown. Android 13+ shows the notification permission prompt;
  /// on iOS Live Activities need no prompt, so this returns [isSupported].
  static Future<bool> requestPermission() => _platform.requestPermission();

  /// Whether Android shows this app's live updates as promoted Live Updates
  /// (status bar chip, top of the shade and Lock Screen). Requires an
  /// Android 16 build with promoted notification support (QPR1 and later)
  /// and the user's permission, which they can revoke in Settings. When it
  /// is `false`, updates still appear as regular ongoing notifications.
  /// Always `false` on other platforms.
  static Future<bool> canPostPromotedNotifications() =>
      _platform.canPostPromotedNotifications();

  /// Starts a live update.
  ///
  /// [pushUpdates] requests a per-activity APNs token on iOS (see
  /// [LiveUpdate.pushTokens]); it needs the Push Notifications capability.
  /// It has no effect on Android, where remote updates arrive as payloads
  /// (see [handleRemotePayload]).
  ///
  /// [iosChannelId] subscribes the Live Activity to an APNs broadcast channel
  /// (iOS 18+), so one push updates every device on that channel, such as a
  /// sports score. Create the channel with APNs' channel management API (see
  /// `tool/send_push.dart`); it needs Broadcast Capability for the App ID.
  /// Broadcasts can update and end activities but not start them. It cannot
  /// be combined with [pushUpdates], throws [LiveUpdateException] before
  /// iOS 18, and is ignored on Android (broadcast there with FCM topics and
  /// [handleRemotePayload]).
  static Future<LiveUpdate> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    _checkPushOptions(pushUpdates, iosChannelId);
    return LiveUpdate._(
      await _platform.start(
        content,
        pushUpdates: pushUpdates,
        iosChannelId: iosChannelId,
      ),
    );
  }

  static void _checkPushOptions(bool pushUpdates, String? channel) {
    if (channel != null && channel.isEmpty) {
      throw ArgumentError.value(channel, 'iosChannelId', 'Must not be empty');
    }
    if (pushUpdates && channel != null) {
      throw ArgumentError(
        'pushUpdates and iosChannelId cannot be combined: an activity receives '
        'either per-activity pushes or broadcasts.',
      );
    }
  }

  /// Updates the running live update identified by [key], or starts a new
  /// one with that key. Use it when your own data has an id, such as an
  /// order number, so repeated calls never create duplicates.
  ///
  /// On Android the key is the update's [LiveUpdate.id] and matches
  /// `live_updates_id` in remote payloads. On iOS the key is stored in the
  /// activity's attributes; push-to-start can set it with
  /// `"attributes": {"key": "..."}`.
  ///
  /// A live update with this key that the user dismissed is not shown again
  /// (platform guidance); on Android it comes back only after [LiveUpdate.end]
  /// for that key, on iOS once the system no longer lists the ended activity.
  /// Use a new key for a new activity.
  ///
  /// [pushUpdates] and [iosChannelId] only apply when a new activity is
  /// started: an existing activity keeps the push setting it was started
  /// with.
  static Future<LiveUpdate> startOrUpdate(
    String key,
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    _checkPushOptions(pushUpdates, iosChannelId);
    return LiveUpdate._(
      await _platform.startOrUpdate(
        key,
        content,
        pushUpdates: pushUpdates,
        iosChannelId: iosChannelId,
      ),
      key,
    );
  }

  /// The running live update identified by [key], if any.
  static Future<LiveUpdate?> find(String key) async =>
      switch (await _platform.idForKey(key)) {
        final id? => LiveUpdate._(id, key),
        null => null,
      };

  /// Button presses on any live update, including presses made while the
  /// app was not running once Dart listens again.
  static Stream<LiveUpdateActionEvent> get onAction => _platform.actions.map(
    (e) => LiveUpdateActionEvent(updateId: e.$1, actionId: e.$2),
  );

  /// Runs [handler] for button presses that arrive while the app is not
  /// running (or no [onAction] listener is active): the plugin starts a
  /// headless Flutter engine, calls [handler] for each press and shuts the
  /// engine down. Call it early, for example in `main`, before `runApp`.
  ///
  /// [handler] must be a top-level or static function annotated with
  /// `@pragma('vm:entry-point')`. It has a few seconds to finish (the system
  /// limits background work). It also runs while the app is open if nothing
  /// listens to [onAction].
  ///
  /// Buttons can be pressed on the Lock Screen, so the handler may run
  /// without the device being unlocked. Make destructive actions require an
  /// unlock with [LiveUpdateAction.requiresUnlock], and keep server-side
  /// actions idempotent and authorized. On iOS, plugins that use platform channels are
  /// only available to it if the app registers them for background engines
  /// (see the README).
  ///
  /// ```dart
  /// @pragma('vm:entry-point')
  /// Future<void> onBackgroundAction(LiveUpdateActionEvent event) async {
  ///   if (event.actionId == 'cancel') await api.cancelOrder(event.updateId);
  /// }
  /// ```
  static Future<void> setBackgroundActionHandler(
    LiveUpdateActionHandler handler,
  ) => registerBackgroundActionHandler(handler);

  /// Currently running live updates started by this app, including ones
  /// started remotely with a push-to-start token.
  static Future<List<LiveUpdate>> active() async => [
    for (final id in await _platform.activeIds())
      LiveUpdate._(id, await _platform.keyForId(id)),
  ];

  /// Live updates that appear while the app runs, including ones started by
  /// a push-to-start notification (iOS) or a remote payload (Android).
  static Stream<LiveUpdate> get onStarted => _platform.events
      .where((e) => e.$2 == 'started')
      .asyncMap((e) async => LiveUpdate._(e.$1, await _keyOrNull(e.$1)));

  static Future<String?> _keyOrNull(String id) async {
    try {
      return await _platform.keyForId(id);
    } on Object {
      return null; // A missing key must not drop the update from the stream.
    }
  }

  /// Ends every live update started by this app.
  static Future<void> endAll() => _platform.endAll();

  /// iOS push-to-start tokens (iOS 17.2+, empty elsewhere). A new listener
  /// first receives the current token, if one is known.
  static Stream<LiveUpdatePushToken> get pushToStartTokens =>
      _platform.pushToStartTokens;

  /// Routes from taps on a live update ([LiveUpdateContent.route]).
  static Stream<String> get onTap => _platform.taps;

  /// Applies a remote payload received by the app on Android, for example
  /// from an FCM data message, and returns whether it was a live_updates
  /// message. Always `false` on iOS, where APNs updates the activity
  /// directly.
  ///
  /// Payload keys: `live_updates_event` (`start`, `update` or `end`),
  /// `live_updates_id` (chosen by the server for remote starts) and
  /// `live_updates_content` (the content as a JSON string, same keys as the
  /// iOS `content-state`), plus `live_updates_dismiss_after` (seconds) for
  /// `end`.
  static Future<bool> handleRemotePayload(Map<String, Object?> data) =>
      _platform.handleRemotePayload(data);
}
