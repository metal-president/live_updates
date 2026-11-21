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

  /// Button presses as `(update id, action id)`.
  Stream<(String, String)> get actions;

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
  Stream<(String, String)> get actions => const Stream.empty();

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
