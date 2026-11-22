import 'dart:async';
import 'dart:ffi' show Void;

import 'package:objective_c/objective_c.dart' as objc;

import '../ios/bindings.g.dart';
import '../models.dart';
import 'buffered_broadcast.dart';
import 'observed_broadcast.dart';
import 'content_encoder.dart';
import 'latest_value_stream.dart';
import 'live_updates_platform.dart';

/// iOS backend: FFIgen bindings to the Swift `LiveUpdatesBridge`.
class IosLiveUpdatesPlatform extends LiveUpdatesPlatform with ContentEncoder {
  @override
  String? get imageDirectory =>
      LiveUpdatesBridge.imageDirectory()?.toDartString();

  @override
  String get missingImageDirectoryHint =>
      'Images need an App Group shared with the widget extension. Run '
      '`dart run live_updates:create_widget` and enable the App Group '
      'capability for Runner and the widget (see the README).';

  late final _taps = BufferedBroadcast<String>(
    (add) => LiveUpdatesBridge.observeTaps(
      ObjCBlock_ffiVoid_NSString.listener((r) => add(r.toDartString())),
    ),
  );
  late final _pushToStart = LatestValueStream<LiveUpdatePushToken>(
    (add) => LiveUpdatesBridge.observePushToStartTokens(
      ObjCBlock_ffiVoid_NSString.listener(
        (t) => add(LiveUpdatePushToken(t.toDartString())),
      ),
    ),
  );
  late final _actions = ObservedBroadcast<(String, String)>(
    keyOf: (e) => e.$1,
    attach: (add, keys) => LiveUpdatesBridge.observeActions(
      ObjCBlock_ffiVoid_NSString.listener((e) {
        final s = e.toDartString();
        final i = s.indexOf('\n');
        add((s.substring(0, i), s.substring(i + 1)));
      }),
      activityIds: _nsList(keys),
    ),
    setFilter: (keys) => LiveUpdatesBridge.setActionFilter(_nsList(keys)),
    detach: LiveUpdatesBridge.unobserveActions,
    requeue: (events) => LiveUpdatesBridge.requeueActions(
      _nsList({for (final (u, a) in events) '$u\n$a'})!,
    ),
  );

  static objc.NSArray? _nsList(Set<String>? values) => values == null
      ? null
      : objc.NSArray.of([for (final v in values) v.toNSString()]);
  final _pushTokens = <String, LatestValueStream<LiveUpdatePushToken>>{};
  final _events = StreamController<(String, String)>.broadcast();
  bool _eventsObserved = false;

  static objc.NSString _ns(String s) => s.toNSString();

  @override
  Future<bool> isSupported() async => LiveUpdatesBridge.isSupported();

  @override
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    final json = await encodeContent(content, {
      'enablePushUpdates': pushUpdates,
      'broadcastChannelId': ?iosChannelId,
    });
    try {
      final id = LiveUpdatesBridge.start(_ns(json));
      if (id == null) throw StateError('ActivityKit returned no activity');
      return id.toDartString();
    } on objc.NSErrorException catch (e) {
      throw LiveUpdateException(e.error.localizedDescription.toDartString());
    }
  }

  Future<void> _await(
    void Function(objc.ObjCBlock<Void Function(objc.NSString?)>) call,
  ) {
    final done = Completer<void>();
    call(
      ObjCBlock_ffiVoid_NSString$1.listener((error) {
        error == null
            ? done.complete()
            : done.completeError(LiveUpdateException(error.toDartString()));
      }),
    );
    return done.future;
  }

  @override
  Future<String> startOrUpdate(
    String key,
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    final json = await encodeContent(content, {
      'enablePushUpdates': pushUpdates,
      'broadcastChannelId': ?iosChannelId,
    });
    final result = Completer<String>();
    LiveUpdatesBridge.startOrUpdate(
      _ns(key),
      json: _ns(json),
      completion: ObjCBlock_ffiVoid_NSString_NSString.listener((id, error) {
        if (id != null) {
          result.complete(id.toDartString());
        } else {
          result.completeError(
            LiveUpdateException(
              error?.toDartString() ?? 'startOrUpdate failed',
            ),
          );
        }
      }),
    );
    return result.future;
  }

  @override
  Future<String?> idForKey(String key) async =>
      LiveUpdatesBridge.idForKey(_ns(key))?.toDartString();

  @override
  Future<String?> keyForId(String id) async =>
      LiveUpdatesBridge.keyForId(_ns(id))?.toDartString();

  @override
  Stream<(String, String)> actions({String? updateId}) =>
      _actions.stream(updateId);

  @override
  Future<void> setBackgroundActionHandler(int dispatcher, int handler) async =>
      LiveUpdatesBridge.setBackgroundActionHandler(
        dispatcher,
        handler: handler,
      );

  @override
  Future<int?> backgroundActionHandler() async {
    final raw = LiveUpdatesBridge.backgroundActionHandler();
    return raw == 0 ? null : raw;
  }

  @override
  Future<List<(String, String)>> takeQueuedActions() async => [
    for (final o in LiveUpdatesBridge.takeQueuedActions().asDart())
      if (objc.NSString.as(o).toDartString() case final s)
        if (s.indexOf('\n') case final at when at > 0)
          (s.substring(0, at), s.substring(at + 1)),
  ];

  @override
  Future<void> backgroundActionsDone() async =>
      LiveUpdatesBridge.backgroundActionsDone();

  @override
  Future<void> update(String id, LiveUpdateContent content) async {
    final json = await encodeContent(content);
    await _await(
      (cb) =>
          LiveUpdatesBridge.update(_ns(id), json: _ns(json), completion: cb),
    );
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
    await _await(
      (cb) => LiveUpdatesBridge.end(
        _ns(id),
        json: json == null ? null : _ns(json),
        dismissAfter: dismissAfter == null
            ? -1
            : dismissAfter.inMilliseconds / 1000,
        completion: cb,
      ),
    );
    unawaited(_pushTokens.remove(id)?.close());
  }

  @override
  Future<List<String>> activeIds() async => [
    for (final o in LiveUpdatesBridge.activeIds().asDart())
      objc.NSString.as(o).toDartString(),
  ];

  @override
  Future<void> endAll() {
    final done = Completer<void>();
    LiveUpdatesBridge.endAll(ObjCBlock_ffiVoid.listener(done.complete));
    return done.future;
  }

  @override
  Stream<(String, String)> get events {
    if (!_eventsObserved) {
      _eventsObserved = true;
      LiveUpdatesBridge.observeActivities(
        ObjCBlock_ffiVoid_NSString.listener((e) {
          final s = e.toDartString();
          final i = s.indexOf(':');
          _events.add((s.substring(i + 1), s.substring(0, i)));
        }),
      );
    }
    return _events.stream;
  }

  @override
  Stream<LiveUpdatePushToken> pushTokens(String id) => _pushTokens
      .putIfAbsent(
        id,
        () => LatestValueStream(
          (add) => LiveUpdatesBridge.observePushTokens(
            _ns(id),
            handler: ObjCBlock_ffiVoid_NSString.listener(
              (t) => add(LiveUpdatePushToken(t.toDartString())),
            ),
          ),
        ),
      )
      .stream;

  @override
  Stream<LiveUpdatePushToken> get pushToStartTokens => _pushToStart.stream;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<bool> handleRemotePayload(Map<String, Object?> data) async => false;
}
