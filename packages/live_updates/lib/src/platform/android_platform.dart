import 'dart:async';
import 'dart:convert';

import 'dart:ui' show PlatformDispatcher;

import 'package:jni/jni.dart';

import '../android/bindings.g.dart';
import '../diagnostics.dart';
import '../models.dart';
import 'buffered_broadcast.dart';
import 'observed_broadcast.dart';
import 'wire.dart';
import 'content_encoder.dart';
import 'live_updates_platform.dart';

/// Android backend: JNIgen bindings to the Java `LiveUpdatesBridge`.
class AndroidLiveUpdatesPlatform extends LiveUpdatesPlatform
    with ContentEncoder {
  @override
  String? get imageDirectory =>
      LiveUpdatesBridge.imageDirectory()?.toDartString(releaseOriginal: true);

  @override
  String get missingImageDirectoryHint => 'live_updates is not attached yet.';

  late final _taps = BufferedBroadcast<String>(
    (add) => LiveUpdatesBridge.observeTaps(
      LiveUpdatesBridge$RouteListener.implement(
        $LiveUpdatesBridge$RouteListener(
          onRoute: (r) => add(r.toDartString(releaseOriginal: true)),
          onRoute$async: true,
        ),
      ),
      _engineId,
    ),
  );
  late final _actions = ObservedBroadcast<(String, String)>(
    keyOf: (e) => e.$1,
    attach: (add, keys) => LiveUpdatesBridge.observeActions(
      LiveUpdatesBridge$ActionListener.implement(
        $LiveUpdatesBridge$ActionListener(
          onAction: (updateId, actionId) => add((
            updateId.toDartString(releaseOriginal: true),
            actionId.toDartString(releaseOriginal: true),
          )),
          onAction$async: true,
        ),
      ),
      _engineId,
      _jList(keys),
    ),
    setFilter: (keys) =>
        LiveUpdatesBridge.setActionFilter(_engineId, _jList(keys)),
    detach: () => LiveUpdatesBridge.unobserveActions(_engineId),
    requeue: (events) => LiveUpdatesBridge.requeueActions(
      JArray.of(JString.type, [
        for (final (u, a) in events) _j(encodePress(u, a)),
      ]),
    ),
  );

  static JArray<JString?>? _jList(Set<String>? values) => values == null
      ? null
      : JArray.of(JString.type, [for (final v in values) _j(v)]);

  /// Identifies this isolate's engine, so the plugin drops its listeners
  /// when the engine goes away.
  static int get _engineId => PlatformDispatcher.instance.engineId ?? 0;
  final _events = StreamController<(String, String)>.broadcast();
  bool _eventsObserved = false;

  static JString _j(String s) => s.toJString();

  /// Runs a synchronous Java call, mapping Java exceptions.
  static T _call<T>(T Function() call) {
    try {
      return call();
    } on JThrowable catch (e) {
      throw LiveUpdateException(e.toString(), reason: _reason(e));
    }
  }

  /// The reason the Java bridge gives for [e]
  /// (`LiveUpdatesBridge.failureReason`).
  static LiveUpdateFailure _reason(JThrowable e) {
    try {
      final throwable = e.as(Throwable.type);
      try {
        return failureFromName(
          LiveUpdatesBridge.failureReason(throwable)
              .toDartString(releaseOriginal: true),
        );
      } finally {
        throwable.release();
      }
    } on Object {
      return LiveUpdateFailure.other;
    }
  }

  @override
  Future<bool> isSupported() async => LiveUpdatesBridge.isSupported;

  @override
  Future<bool> requestPermission() {
    final result = Completer<bool>();
    LiveUpdatesBridge.requestPermission(
      LiveUpdatesBridge$ResultListener.implement(
        $LiveUpdatesBridge$ResultListener(
          onResult: result.complete,
          onResult$async: true,
        ),
      ),
    );
    return result.future;
  }

  @override
  Future<bool> canPostPromotedNotifications() async =>
      LiveUpdatesBridge.canPostPromotedNotifications();

  @override
  Future<bool> isPromoted(String id) async =>
      _call(() => LiveUpdatesBridge.isPromoted(_j(id)));

  @override
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    warnIfUntitled(content);
    final json = await encodeContent(content);
    return _call(
      () =>
          LiveUpdatesBridge.start(_j(json)).toDartString(releaseOriginal: true),
    );
  }

  @override
  Future<String> startOrUpdate(
    String key,
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    warnIfUntitled(content);
    final json = await encodeContent(content);
    return _call(
      () => LiveUpdatesBridge.startOrUpdate(
        _j(key),
        _j(json),
      ).toDartString(releaseOriginal: true),
    );
  }

  @override
  Future<String?> idForKey(String key) async =>
      LiveUpdatesBridge.idForKey(_j(key))?.toDartString(releaseOriginal: true);

  @override
  Future<String?> keyForId(String id) async =>
      LiveUpdatesBridge.keyForId(_j(id))?.toDartString(releaseOriginal: true);

  @override
  Future<String?> stateForId(String id) async =>
      LiveUpdatesBridge.stateOf(_j(id))?.toDartString(releaseOriginal: true);

  // The key of a keyed update is its id.
  @override
  Future<String?> stateForKey(String key) => stateForId(key);

  @override
  Stream<(String, String)> actions({String? updateId}) =>
      _actions.stream(updateId);

  @override
  Future<void> setBackgroundActionHandler(int dispatcher, int handler) async =>
      _call(
        () => LiveUpdatesBridge.setBackgroundActionHandler(dispatcher, handler),
      );

  @override
  Future<int?> backgroundActionHandler() async {
    final raw = LiveUpdatesBridge.backgroundActionHandler();
    return raw == 0 ? null : raw;
  }

  @override
  Future<List<(String, String)>> takeQueuedActions() async {
    final queued = LiveUpdatesBridge.takeQueuedActions();
    return [
      for (var i = 0; i < queued.length; i++)
        if (queued[i]?.toDartString(releaseOriginal: true) case final s?)
          ?parsePress(s),
    ];
  }

  @override
  Future<void> backgroundActionsDone() async =>
      LiveUpdatesBridge.backgroundActionsDone();

  @override
  Future<void> update(String id, LiveUpdateContent content) async {
    warnIfUntitled(content);
    final json = await encodeContent(content);
    _call(() => LiveUpdatesBridge.update(_j(id), _j(json)));
  }

  @override
  Future<void> end(
    String id, {
    LiveUpdateContent? finalContent,
    Duration? dismissAfter,
  }) async {
    final json = finalContent == null
        ? null
        : await encodeContent(finalContent);
    _call(
      () => LiveUpdatesBridge.end(
        _j(id),
        json == null ? null : _j(json),
        // No duration given (-1) keeps the ended update for four hours, as
        // the iOS default policy does; 0 removes it immediately.
        dismissSeconds(dismissAfter),
      ),
    );
  }

  @override
  Future<List<String>> activeIds() async {
    final ids = LiveUpdatesBridge.activeIds();
    return [
      for (var i = 0; i < ids.length; i++)
        ids[i]!.toDartString(releaseOriginal: true),
    ];
  }

  @override
  Future<void> endAll() async => _call(LiveUpdatesBridge.endAll);

  @override
  Stream<(String, String)> get events {
    if (!_eventsObserved) {
      _eventsObserved = true;
      LiveUpdatesBridge.observeEvents(
        LiveUpdatesBridge$EventListener.implement(
          $LiveUpdatesBridge$EventListener(
            onEvent: (e) {
              final event = parseEvent(e.toDartString(releaseOriginal: true));
              if (event != null) _events.add(event);
            },
            onEvent$async: true,
          ),
        ),
        _engineId,
      );
    }
    return _events.stream;
  }

  @override
  Stream<LiveUpdatePushToken> pushTokens(String id) => const Stream.empty();

  @override
  Stream<LiveUpdatePushToken> get pushToStartTokens => const Stream.empty();

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<bool> handleRemotePayload(Map<String, Object?> data) async =>
      _call(() => LiveUpdatesBridge.handleRemotePayload(_j(jsonEncode(data))));

  @override
  Future<bool> canSchedule() async => LiveUpdatesBridge.canSchedule();

  @override
  Future<bool> canScheduleExactly() async =>
      LiveUpdatesBridge.canScheduleExactly();

  @override
  Future<bool> openExactAlarmSettings() async =>
      LiveUpdatesBridge.openExactAlarmSettings();

  @override
  Future<bool> openSettings() async => LiveUpdatesBridge.openSettings();

  @override
  Future<LiveUpdateDiagnostics> diagnose({
    String androidChannelId = 'live_updates',
  }) async {
    final channel = _j(androidChannelId);
    final String json;
    try {
      json = LiveUpdatesBridge.diagnosticsJson(channel)
          .toDartString(releaseOriginal: true);
    } finally {
      channel.release();
    }
    return androidDiagnostics(switch (jsonDecode(json)) {
      final Map<String, Object?> facts => facts,
      _ => const {},
    }, channelId: androidChannelId);
  }

  @override
  Future<void> schedule(
    String key,
    LiveUpdateContent content, {
    required DateTime at,
    bool pushUpdates = false,
    AndroidScheduleOptions android = const AndroidScheduleOptions(),
  }) async {
    warnIfUntitled(content);
    final json = await encodeContent(content, const {}, at);
    _call(
      () => LiveUpdatesBridge.schedule(
        _j(key),
        _j(json),
        at.millisecondsSinceEpoch,
        android.exact,
        android.window.inMilliseconds,
      ),
    );
  }

  @override
  Future<void> reschedule(
    String key, {
    required DateTime at,
    LiveUpdateContent? content,
  }) async {
    if (content != null) warnIfUntitled(content);
    final json = content == null
        ? null
        : await encodeContent(content, const {}, at);
    _call(
      () => LiveUpdatesBridge.reschedule(
        _j(key),
        json == null ? null : _j(json),
        at.millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<List<(String, DateTime)>> scheduled() async => parseSchedules(
    LiveUpdatesBridge.scheduledJson().toDartString(releaseOriginal: true),
  );

  @override
  Future<void> cancelAllScheduled() async =>
      _call(LiveUpdatesBridge.cancelAllScheduled);

  @override
  Future<void> cancelScheduled(String key) async =>
      _call(() => LiveUpdatesBridge.cancelScheduled(_j(key)));
}
