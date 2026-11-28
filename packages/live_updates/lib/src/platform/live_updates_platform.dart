import '../diagnostics.dart';
import '../models.dart';
// dart:ffi based backends are only imported where dart:ffi exists, so the
// package still compiles (as a no-op) for the web.
import 'default_platform_stub.dart'
    if (dart.library.ffi) 'default_platform_native.dart';

/// Native backend used by [LiveUpdates]. Implemented with FFIgen on iOS and
/// JNIgen on Android; [NoopLiveUpdatesPlatform] everywhere else.
///
/// Custom implementations (for example test fakes) should extend
/// [NoopLiveUpdatesPlatform]: methods may be added to this class in minor
/// releases, and the no-op base keeps such implementations compiling.
abstract class LiveUpdatesPlatform {
  /// The active backend. Replace in tests with a fake.
  static LiveUpdatesPlatform instance = createDefaultPlatform();

  /// See [LiveUpdates.isSupported].
  Future<bool> isSupported();

  /// See [LiveUpdates.requestPermission].
  Future<bool> requestPermission() => isSupported();

  /// See [LiveUpdates.canPostPromotedNotifications].
  Future<bool> canPostPromotedNotifications() async => false;

  /// See [LiveUpdate.isPromoted].
  Future<bool> isPromoted(String id) async => false;

  /// Starts a live update and returns its id.
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  });

  /// Updates the live update with key [key] or starts one; returns its id.
  Future<String> startOrUpdate(
    String key,
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  });

  /// Id of the running live update with key [key].
  Future<String?> idForKey(String key);

  /// Key of the live update [id], or `null` when it was started without one.
  Future<String?> keyForId(String id) async => null;

  /// Current state name of the live update [id] (`active`, `stale`, `ended`,
  /// `dismissed`), or `null` when the platform no longer knows it.
  Future<String?> stateForId(String id) async => null;

  /// Current state name of the live update with key [key], as [stateForId].
  Future<String?> stateForKey(String key) async => null;

  /// Button presses as `(update id, action id)`, of update [updateId] only
  /// when given. Presses go to the app only while one of these streams is
  /// listened to; otherwise the background action handler runs.
  Stream<(String, String)> actions({String? updateId});

  /// Stores the callback handles used to run [LiveUpdates.setBackgroundActionHandler]'s
  /// handler in a headless engine.
  Future<void> setBackgroundActionHandler(int dispatcher, int handler) async {}

  /// Raw callback handle of the background action handler, if registered.
  Future<int?> backgroundActionHandler() async => null;

  /// Removes and returns the presses queued for the background handler.
  Future<List<(String, String)>> takeQueuedActions() async => const [];

  /// Signals that the background handler finished.
  Future<void> backgroundActionsDone() async {}

  /// Updates the live update with [id].
  Future<void> update(String id, LiveUpdateContent content);

  /// Ends the live update with [id].
  Future<void> end(
    String id, {
    LiveUpdateContent? finalContent,
    Duration? dismissAfter,
  });

  /// Ids of live updates currently shown.
  Future<List<String>> activeIds();

  /// See [LiveUpdates.preloadIcons].
  Future<void> preloadIcons(List<String> assets) async {}

  /// Ends every live update of this app.
  Future<void> endAll();

  /// Lifecycle events as `(id, event)`; event is `started`, `active`,
  /// `stale`, `ended` or `dismissed`.
  Stream<(String, String)> get events;

  /// Push tokens for the live update with [id].
  Stream<LiveUpdatePushToken> pushTokens(String id);

  /// Push-to-start tokens.
  Stream<LiveUpdatePushToken> get pushToStartTokens;

  /// Tap routes.
  Stream<String> get taps;

  /// Applies a remote payload; `false` if it is not a live_updates message.
  Future<bool> handleRemotePayload(Map<String, Object?> data);

  /// See [LiveUpdates.canSchedule].
  Future<bool> canSchedule() async => false;

  /// See [LiveUpdates.canScheduleExactly].
  Future<bool> canScheduleExactly() async => false;

  /// See [LiveUpdates.openExactAlarmSettings].
  Future<bool> openExactAlarmSettings() async => false;

  /// See [LiveUpdates.openSettings].
  Future<bool> openSettings() async => false;

  /// See [LiveUpdates.diagnose].
  Future<LiveUpdateDiagnostics> diagnose({
    String androidChannelId = 'live_updates',
  }) async => const LiveUpdateDiagnostics.unsupported();

  /// Schedules [content] to be shown with [key] at [at], replacing a
  /// schedule with that key. Shows it now when [at] is not in the future.
  Future<void> schedule(
    String key,
    LiveUpdateContent content, {
    required DateTime at,
    bool pushUpdates = false,
    AndroidScheduleOptions android = const AndroidScheduleOptions(),
  }) async {}

  /// Moves the schedule with [key] to [at], with [content] instead of the
  /// scheduled content when given. Throws [LiveUpdateException] when no
  /// live update with [key] is scheduled.
  Future<void> reschedule(
    String key, {
    required DateTime at,
    LiveUpdateContent? content,
  }) async {}

  /// Scheduled live updates as `(key, time)`.
  Future<List<(String, DateTime)>> scheduled() async => const [];

  /// Cancels the schedule with [key], if any.
  Future<void> cancelScheduled(String key) async {}

  /// Cancels every schedule.
  Future<void> cancelAllScheduled() async {}
}

/// Backend for unsupported platforms: every call succeeds and does nothing.
class NoopLiveUpdatesPlatform extends LiveUpdatesPlatform {
  int _next = 0;

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async => 'noop-${_next++}';

  @override
  Future<String> startOrUpdate(
    String key,
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async => key;

  @override
  Future<String?> idForKey(String key) async => null;

  @override
  Stream<(String, String)> actions({String? updateId}) => const Stream.empty();

  @override
  Future<void> update(String id, LiveUpdateContent content) async {}

  @override
  Future<void> end(
    String id, {
    LiveUpdateContent? finalContent,
    Duration? dismissAfter,
  }) async {}

  @override
  Future<List<String>> activeIds() async => const [];

  @override
  Future<void> endAll() async {}

  @override
  Stream<(String, String)> get events => const Stream.empty();

  @override
  Stream<LiveUpdatePushToken> pushTokens(String id) => const Stream.empty();

  @override
  Stream<LiveUpdatePushToken> get pushToStartTokens => const Stream.empty();

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<bool> handleRemotePayload(Map<String, Object?> data) async => false;
}
