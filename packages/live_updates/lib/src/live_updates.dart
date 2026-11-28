import 'background.dart';
import 'diagnostics.dart';
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

  /// Replaces the shown content. Throws a [LiveUpdateException] when the
  /// update has ended, and on Android also when the user dismissed it or
  /// while notifications are turned off for the app or for its channel
  /// ([LiveUpdateFailure.disabled]).
  Future<void> update(LiveUpdateContent content) =>
      _platform.update(id, content);

  /// Ends the update. [finalContent] (or, without it, the content shown last)
  /// stays visible for [dismissAfter], at most four hours, which is also the
  /// default when [dismissAfter] is `null`; `Duration.zero` removes it
  /// immediately. It shows no buttons or running timers (nor timer or
  /// stopwatch metrics). On iOS it stays on the Lock Screen (the system may
  /// remove it earlier). On Android it becomes a regular notification that
  /// is no longer ongoing or promoted; the user can swipe it away, and its
  /// removal is not reported as [LiveUpdateState.dismissed]. Below Android
  /// 8.0 the system cannot remove it later: there only [finalContent] stays,
  /// until the user dismisses it.
  Future<void> end({LiveUpdateContent? finalContent, Duration? dismissAfter}) =>
      _platform.end(id, finalContent: finalContent, dismissAfter: dismissAfter);

  /// Whether Android promoted this update to a Live Update (status bar chip,
  /// top of the shade and Lock Screen) as it is shown now.
  ///
  /// This is the system's actual decision: besides the permission reported by
  /// [LiveUpdates.canPostPromotedNotifications], it depends on the promotion
  /// requirements (such as [AndroidLiveUpdateMode.liveUpdate] and a title),
  /// the user's settings and device maker criteria. `false` when the update
  /// is not shown, below Android 16 and on other platforms.
  ///
  /// It reflects the notification as the system currently lists it. The
  /// system decides on promotion after the notification is posted and updates
  /// its list asynchronously, so this may be `false` for a moment right after
  /// [LiveUpdates.start] or [update].
  Future<bool> isPromoted() => _platform.isPromoted(id);

  /// The current state of this live update, or `null` when the platform no
  /// longer knows it (it ended and is no longer shown, or was never shown).
  /// Use it to set up your UI, for example after an app restart, and [states]
  /// for later changes.
  ///
  /// [LiveUpdateState.ended] means it ended and is still shown (see
  /// [end]). [LiveUpdateState.dismissed] is reported on iOS while the system
  /// still lists the dismissed activity; on Android until the app ends the
  /// update (the plugin remembers the dismissal, see
  /// [LiveUpdates.startOrUpdate]).
  Future<LiveUpdateState?> state() async =>
      switch (await _platform.stateForId(id)) {
        final name? => _stateFromName(name),
        null => null,
      };

  /// Lifecycle changes of this live update, such as the user dismissing it or
  /// the update becoming stale at [LiveUpdateContent.endAt].
  Stream<LiveUpdateState> get states => _platform.events
      .where((e) => e.$1 == id)
      .map((e) => _stateFromName(e.$2))
      .where((s) => s != null)
      .cast<LiveUpdateState>();

  /// Presses of this update's buttons ([LiveUpdateContent.actions]).
  ///
  /// While this is listened to, this update's presses go to the app instead
  /// of the background action handler. Presses of other updates go to
  /// [LiveUpdates.onAction] if it is listened to, else to the background
  /// handler.
  Stream<String> get actions =>
      _platform.actions(updateId: id).map((e) => e.$2);

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

/// A live update scheduled with [LiveUpdates.schedule] that has not been
/// shown yet. It is identified by its [key]: scheduling again with that key
/// replaces it.
final class ScheduledLiveUpdate {
  // The platforms keep the time in milliseconds: local time with that
  // precision makes a handle equal to the one [LiveUpdates.findScheduled]
  // and [LiveUpdates.scheduled] return.
  ScheduledLiveUpdate._(this.key, DateTime at)
    : at = DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch);

  /// The key the update is shown with ([LiveUpdate.key] once it is shown).
  final String key;

  /// When the update is shown, in local time to the millisecond.
  final DateTime at;

  LiveUpdatesPlatform get _platform => LiveUpdatesPlatform.instance;

  /// Moves the update to [at] and, when given, replaces its content. With
  /// neither, it is scheduled again unchanged. A time that is not in the
  /// future shows it now.
  ///
  /// On iOS this ends the scheduled Live Activity and requests a new one
  /// (ActivityKit does not change the content of an activity before it
  /// starts), so it must be called while the app is in the foreground.
  ///
  /// Throws [LiveUpdateException] when nothing is scheduled with [key] any
  /// more, for example because it was shown or cancelled.
  Future<ScheduledLiveUpdate> reschedule({
    DateTime? at,
    LiveUpdateContent? content,
  }) async {
    final when = at ?? this.at;
    await _platform.reschedule(key, at: when, content: content);
    return ScheduledLiveUpdate._(key, when);
  }

  /// Cancels the update, if it is still scheduled. A live update that was
  /// already shown keeps running: end it with [LiveUpdate.end].
  Future<void> cancel() => _platform.cancelScheduled(key);

  @override
  bool operator ==(Object other) =>
      other is ScheduledLiveUpdate && other.key == key && other.at == at;

  @override
  int get hashCode => Object.hash(key, at);

  @override
  // The key may be your own id, such as an order number: keep it out of logs.
  String toString() => 'ScheduledLiveUpdate(at: $at)';
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
  /// `false` below iOS 16.2 and on platforms other than iOS and Android.
  static Future<bool> isSupported() => _platform.isSupported();

  /// Asks for the permission needed to show live updates and returns whether
  /// they can be shown. Android 13+ shows the notification permission prompt;
  /// on iOS Live Activities need no prompt, so this returns [isSupported].
  ///
  /// On Android 13+, while the permission is not granted, it returns `false`
  /// without a prompt when no activity is attached to the Flutter engine
  /// (for example in a background handler), and when the user has denied
  /// the permission more than once: the system then no longer shows the
  /// prompt, and the user can only allow notifications in Settings
  /// ([openSettings]).
  ///
  /// On every Android version it also returns `false` when no prompt is
  /// needed but notifications are turned off for the app; below Android 13
  /// there is no prompt and it returns [isSupported].
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
  /// Throws a [LiveUpdateException] when it cannot be shown: on iOS when Live
  /// Activities are turned off for the app, the system limit of running
  /// activities is reached, the app is in the background or the device or
  /// iOS version does not support the call; on Android when
  /// notifications are turned off for the app or for its channel. Check
  /// [isSupported] before you offer to track something on the Lock Screen
  /// (it does not cover a turned-off Android channel).
  /// [LiveUpdateException.reason] tells these cases apart:
  /// [LiveUpdateFailure.disabled] (offer [openSettings]),
  /// [LiveUpdateFailure.limitReached], [LiveUpdateFailure.notInForeground]
  /// and [LiveUpdateFailure.unsupported].
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
  /// A live update with this key that ended ([LiveUpdate.end]) and is still
  /// visible is replaced by the new one. One that the user dismissed is not
  /// shown again (platform guidance); on Android it comes back only after
  /// [LiveUpdate.end] for that key, on iOS once the system no longer lists
  /// the dismissed activity. Use a new key for a new activity.
  ///
  /// Throws a [LiveUpdateException] when a new live update cannot be shown,
  /// as [start] does; on Android also when updating a running one while
  /// notifications are turned off for the app or for its channel (as
  /// [LiveUpdate.update]). See [LiveUpdateException.reason].
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

  /// The current state of the live update with [key], as [LiveUpdate.state]:
  /// a running one if there is one, else one that ended and is still shown,
  /// else one the user dismissed. Unlike [find], it also reports updates that
  /// have ended.
  static Future<LiveUpdateState?> stateOf(String key) async =>
      switch (await _platform.stateForKey(key)) {
        final name? => _stateFromName(name),
        null => null,
      };

  /// The running live update identified by [key], if any.
  static Future<LiveUpdate?> find(String key) async =>
      switch (await _platform.idForKey(key)) {
        final id? => LiveUpdate._(id, key),
        null => null,
      };

  /// Button presses on any live update, while the app is in the foreground.
  /// Presses made while it was in the background are run by the background
  /// action handler, or, without one, delivered here once the app listens in
  /// the foreground.
  static Stream<LiveUpdateActionEvent> get onAction => _platform.actions().map(
    (e) => LiveUpdateActionEvent(updateId: e.$1, actionId: e.$2),
  );

  /// Runs [handler] for button presses made while the app is in the
  /// background or not running: the plugin starts a headless Flutter engine,
  /// calls [handler] for each press and shuts the engine down. Call it early, for example in `main`, before `runApp`.
  ///
  /// [handler] must be a top-level or static function annotated with
  /// `@pragma('vm:entry-point')`. It has a few seconds to finish (the system
  /// limits background work). It also runs while the app is open for presses
  /// that no [onAction] (or that update's [LiveUpdate.actions]) listener
  /// takes, and for an open-app press that no listener takes within a few
  /// seconds of the launch.
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
  /// started remotely with a push-to-start token. Ended and dismissed ones
  /// are not included, nor scheduled ones that have not been shown yet
  /// (see [scheduled]).
  static Future<List<LiveUpdate>> active() async => [
    for (final id in await _platform.activeIds())
      LiveUpdate._(id, await _platform.keyForId(id)),
  ];

  /// Live updates that appear while the app runs, including ones started by
  /// a push-to-start notification (iOS), a remote payload (Android) or a
  /// schedule ([schedule]) when its time comes.
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

  /// Ends and removes every live update started by this app, also ended
  /// ones that are still visible ([LiveUpdate.end]), and, unless
  /// [includeScheduled] is `false`, cancels every scheduled one that has not
  /// been shown yet ([cancelAllScheduled]), for example when the user logs
  /// out or switches accounts.
  static Future<void> endAll({bool includeScheduled = true}) async {
    if (includeScheduled) await _platform.cancelAllScheduled();
    await _platform.endAll();
  }

  /// Whether live updates can be scheduled with [schedule] on this device
  /// right now: on iOS 26 and later when Live Activities are enabled for the
  /// app, on Android when [isSupported]. Always `false` before iOS 26 and on
  /// platforms other than iOS and Android.
  static Future<bool> canSchedule() => _platform.canSchedule();

  /// Shows [content] as the live update identified by [key] at [at], as
  /// [startOrUpdate] would at that time: a running live update with [key] is
  /// updated, otherwise a new one starts. Scheduling again with the same key
  /// replaces the earlier schedule. When [at] is not in the future, the
  /// update is shown now.
  ///
  /// The app does not need to run at that time. A scheduled update is not
  /// part of [active] or [find] until it is shown; it then appears on
  /// [onStarted] while the app runs. Use [scheduled] and [findScheduled] to
  /// list or look up schedules. [startOrUpdate] with the same key does not
  /// cancel a schedule; [cancelScheduled], [cancelAllScheduled] and [endAll]
  /// do.
  ///
  /// iOS (26 and later): the system starts the Live Activity and presents
  /// an alert: [IosLiveUpdateOptions.alert], else [LiveUpdateContent.alert],
  /// else the public text ([LiveUpdateContent.publicContent]) or the title
  /// and body.
  /// Call this while the app is in the foreground; it throws
  /// [LiveUpdateException] in the background
  /// ([LiveUpdateFailure.notInForeground]), before iOS 26
  /// ([LiveUpdateFailure.unsupported]; check [canSchedule]) and when too
  /// many activities are running or scheduled
  /// ([LiveUpdateFailure.limitReached]); a scheduled activity counts toward
  /// that limit until it starts. When the limit is reached while replacing
  /// the schedule with [key] for a time in the future, the earlier schedule
  /// is cancelled and the request tried again; if that fails too, the error
  /// is thrown and the earlier schedule restored if the limit allows.
  /// [pushUpdates] requests a per-activity APNs token, which
  /// is issued only once the activity starts ([LiveUpdate.pushTokens] of the
  /// update from [onStarted] or [find]). If a live update with [key] is
  /// running at that time, the system shows both until the app runs; the
  /// plugin then ends the older one.
  ///
  /// Android: an alarm posts the notification. It is on time only with
  /// exact alarms ([canScheduleExactly], [AndroidScheduleOptions]),
  /// otherwise within [AndroidScheduleOptions.window]. Schedules survive
  /// reboots, app updates and time zone changes. A force-stopped app gets no
  /// alarms; the plugin sets them again the next time the app starts and
  /// shows overdue ones then.
  ///
  /// On other platforms this does nothing.
  static Future<ScheduledLiveUpdate> schedule(
    String key,
    LiveUpdateContent content, {
    required DateTime at,
    bool pushUpdates = false,
    AndroidScheduleOptions android = const AndroidScheduleOptions(),
  }) async {
    if (android.window.isNegative) {
      throw ArgumentError.value(
        android.window,
        'android.window',
        'Must not be negative',
      );
    }
    await _platform.schedule(
      key,
      content,
      at: at,
      pushUpdates: pushUpdates,
      android: android,
    );
    return ScheduledLiveUpdate._(key, at);
  }

  /// Live updates scheduled with [schedule] that have not been shown yet,
  /// in the order they are due.
  static Future<List<ScheduledLiveUpdate>> scheduled() async {
    // Same time: by key, so the order does not depend on the platform.
    final list = [...await _platform.scheduled()]
      ..sort((a, b) {
        final byTime = a.$2.compareTo(b.$2);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (key, at) in list) ScheduledLiveUpdate._(key, at)];
  }

  /// The live update scheduled with [key] that has not been shown yet, if
  /// any.
  static Future<ScheduledLiveUpdate?> findScheduled(String key) async {
    for (final (k, at) in await _platform.scheduled()) {
      if (k == key) return ScheduledLiveUpdate._(k, at);
    }
    return null;
  }

  /// Cancels the live update scheduled with [key], if any. Same as
  /// [ScheduledLiveUpdate.cancel].
  static Future<void> cancelScheduled(String key) =>
      _platform.cancelScheduled(key);

  /// Cancels every live update scheduled with [schedule] that has not been
  /// shown yet. Running live updates are not affected; [endAll] ends those
  /// and cancels schedules too.
  static Future<void> cancelAllScheduled() => _platform.cancelAllScheduled();

  /// Whether scheduled live updates are shown on time on Android, which
  /// needs exact alarms: the app must declare the `SCHEDULE_EXACT_ALARM`
  /// permission (this package does not), and from Android 14 on the user
  /// must allow it, as it is denied by default for most apps (see
  /// [openExactAlarmSettings]). Always `true` below Android 12, where
  /// every app may set exact alarms. When it is `false`, scheduled updates
  /// appear within [AndroidScheduleOptions.window]. Always `false` on
  /// other platforms.
  static Future<bool> canScheduleExactly() => _platform.canScheduleExactly();

  /// Opens the system screen where the user allows this app to set exact
  /// alarms (Android 12 and later), and returns whether it was opened.
  /// `false` below Android 12, when the app does not declare
  /// `SCHEDULE_EXACT_ALARM`, and on other platforms. Check
  /// [canScheduleExactly] again when the app returns to the foreground.
  static Future<bool> openExactAlarmSettings() =>
      _platform.openExactAlarmSettings();

  /// Opens the system screen where the user turns live updates back on, and
  /// returns whether it was opened: the app's page in Settings on iOS, the
  /// app's notification settings on Android 8.0 and later, and the app's
  /// details below Android 8.0.
  /// Offer it when a call fails with [LiveUpdateFailure.disabled], or on
  /// Android when [isSupported] or [requestPermission] returns `false`, and
  /// check again when the app returns to the foreground. Call it while the
  /// app is in the foreground; from the background Android may not open the
  /// screen even when this returns `true`. Returns `false` on other
  /// platforms and on iOS versions where the plugin does nothing (below
  /// iOS 16.2, or when the widget extension does not support the running
  /// iOS).
  static Future<bool> openSettings() => _platform.openSettings();

  /// Checks, in one call, why live updates may not appear on this device,
  /// and returns one item per check with a status and a hint. Print it while
  /// setting up (its `toString()` is a readable report), or show it in a
  /// debug screen.
  ///
  /// iOS: the iOS version (16.2 for Live Activities; buttons need 17.0,
  /// push-to-start 17.2 and scheduling 26), the widget extension made by
  /// `create ios`, `NSSupportsLiveActivities`, whether the user allows Live
  /// Activities, the App Group and the tap URL scheme.
  ///
  /// Android: the Android version (Live Updates from Android 16 QPR1, else
  /// an ongoing notification), notifications and the permission, the
  /// notification channel [androidChannelId] (use the
  /// [AndroidLiveUpdateOptions.channelId] you pass), promoted notifications
  /// ([canPostPromotedNotifications]), exact alarms ([canScheduleExactly])
  /// and the default icon meta-data.
  ///
  /// Elsewhere it reports that live updates do nothing on this platform.
  ///
  /// The device remains the reference: a check that passes does not mean
  /// the system shows every update (for example, iOS limits how many Live
  /// Activities run, and Android decides on promotion).
  static Future<LiveUpdateDiagnostics> diagnose({
    String androidChannelId = 'live_updates',
  }) => _platform.diagnose(androidChannelId: androidChannelId);

  /// Copies Flutter assets used as [LiveUpdateIcon.asset] icons into the
  /// App Group shared with the iOS widget extension, so that content sent by
  /// a push can name them.
  ///
  /// A push updates the Live Activity without running the app, so the
  /// widget can only show asset icons that the app stored before. Local
  /// [LiveUpdates.start] and [LiveUpdate.update] calls store their own
  /// icons, so this is only needed for icons that first appear in a push.
  ///
  /// [assets] are asset names such as `assets/icons/parcel.png`, or folders
  /// ending in `/` such as `assets/icons/` for every image under them. Call
  /// it at app start: it also refreshes icons whose asset changed in an app
  /// update. On Android (which reads assets from the app package) it does
  /// nothing.
  ///
  /// Throws a [LiveUpdateException] on iOS when no App Group is set up (see
  /// `create ios`).
  static Future<void> preloadIcons(List<String> assets) =>
      _platform.preloadIcons(assets);

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
  /// `end`: how long the ended update stays, at most and by default four
  /// hours, as `dismissAfter` of [LiveUpdate.end].
  static Future<bool> handleRemotePayload(Map<String, Object?> data) =>
      _platform.handleRemotePayload(data);
}
