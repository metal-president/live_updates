import 'dart:async';
import 'dart:convert';

import 'package:jni/jni.dart';

import '../android/bindings.g.dart';
import '../models.dart';
import 'buffered_broadcast.dart';
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
    ),
  );
  late final _actions = BufferedBroadcast<(String, String)>(
    (add) => LiveUpdatesBridge.observeActions(
      LiveUpdatesBridge$ActionListener.implement(
        $LiveUpdatesBridge$ActionListener(
          onAction: (updateId, actionId) => add((
            updateId.toDartString(releaseOriginal: true),
            actionId.toDartString(releaseOriginal: true),
          )),
          onAction$async: true,
        ),
      ),
    ),
  );
  final _events = StreamController<(String, String)>.broadcast();
  bool _eventsObserved = false;

  static JString _j(String s) => s.toJString();

  /// Runs a synchronous Java call, mapping Java exceptions.
  static T _call<T>(T Function() call) {
    try {
      return call();
    } on JThrowable catch (e) {
      throw LiveUpdateException(e.toString());
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
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
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
  Stream<(String, String)> get actions => _actions.stream;

  @override
  Future<void> update(String id, LiveUpdateContent content) async {
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
        // Android has no system default policy: keep final content until
        // dismissed when no duration is given (-1), remove immediately for 0.
        dismissAfter == null ? -1 : dismissAfter.inMilliseconds / 1000,
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
              final s = e.toDartString(releaseOriginal: true);
              final i = s.indexOf(':');
              _events.add((s.substring(i + 1), s.substring(0, i)));
            },
            onEvent$async: true,
          ),
        ),
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
}
