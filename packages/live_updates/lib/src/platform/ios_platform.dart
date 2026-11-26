import 'dart:async';
import 'dart:ffi' show Void;
import 'dart:ui' show PlatformDispatcher;

import 'package:objective_c/objective_c.dart' as objc;

import '../ios/bindings.g.dart';
import '../models.dart';
import 'buffered_broadcast.dart';
import 'observed_broadcast.dart';
import 'wire.dart';
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
      '`dart run live_updates:create ios` and enable the App Group '
      'capability for Runner and the widget (see the README).';

  @override
  bool get storesIconAssets => true;

  @override
  Future<void> preloadIcons(List<String> assets) => storeIconAssets(assets);

  late final _taps = BufferedBroadcast<String>(
    (add) => LiveUpdatesBridge.observeTaps(
      ObjCBlock_ffiVoid_NSString.listener((r) => add(r.toDartString())),
      engineId: _engineId,
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
        if (parsePress(e.toDartString()) case final press?) add(press);
      }),
      activityIds: _nsList(keys),
      engineId: _engineId,
    ),
    setFilter: (keys) =>
        LiveUpdatesBridge.setActionFilter(_nsList(keys), engineId: _engineId),
    detach: () => LiveUpdatesBridge.unobserveActions(_engineId),
    requeue: (events) => LiveUpdatesBridge.requeueActions(
      objc.NSArray.of([
        for (final (u, a) in events) encodePress(u, a).toNSString(),
      ]),
    ),
  );

  /// Identifies this isolate's engine, so the plugin drops its handlers
  /// when the engine goes away.
  static int get _engineId => PlatformDispatcher.instance.engineId ?? 0;

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
  Future<String?> stateForId(String id) async =>
      LiveUpdatesBridge.stateForId(_ns(id))?.toDartString();

  @override
  Future<String?> stateForKey(String key) async =>
      LiveUpdatesBridge.stateForKey(_ns(key))?.toDartString();

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
      ?parsePress(objc.NSString.as(o).toDartString()),
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
        dismissAfter: dismissSeconds(dismissAfter),
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
  Future<void> endAll() async {
    final done = Completer<void>();
    LiveUpdatesBridge.endAll(ObjCBlock_ffiVoid.listener(done.complete));
    await done.future;
    _closePushTokens(_pushTokens.keys.toList());
  }

  void _closePushTokens(Iterable<String> ids) {
    for (final id in ids) {
      unawaited(_pushTokens.remove(id)?.close());
    }
  }

  @override
  Stream<(String, String)> get events {
    if (!_eventsObserved) {
      _eventsObserved = true;
      LiveUpdatesBridge.observeActivities(
        ObjCBlock_ffiVoid_NSString.listener((e) {
          final event = parseEvent(e.toDartString());
          if (event == null) return;
          // Ended remotely or by the system: its token stream is done too.
          if (event.$2 == 'ended' || event.$2 == 'dismissed') {
            _closePushTokens([event.$1]);
          }
          _events.add(event);
        }),
        engineId: _engineId,
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

  @override
  Future<bool> canSchedule() async => LiveUpdatesBridge.canSchedule();

  @override
  Future<void> schedule(
    String key,
    LiveUpdateContent content, {
    required DateTime at,
    bool pushUpdates = false,
    AndroidScheduleOptions android = const AndroidScheduleOptions(),
  }) async {
    final json = await encodeContent(content, {
      'enablePushUpdates': pushUpdates,
    }, at);
    await _await(
      (cb) => LiveUpdatesBridge.schedule(
        _ns(key),
        json: _ns(json),
        at: at.millisecondsSinceEpoch / 1000,
        completion: cb,
      ),
    );
  }

  @override
  Future<void> reschedule(
    String key, {
    required DateTime at,
    LiveUpdateContent? content,
  }) async {
    final json = content == null
        ? null
        : await encodeContent(content, const {}, at);
    await _await(
      (cb) => LiveUpdatesBridge.reschedule(
        _ns(key),
        json: json == null ? null : _ns(json),
        at: at.millisecondsSinceEpoch / 1000,
        completion: cb,
      ),
    );
  }

  @override
  Future<List<(String, DateTime)>> scheduled() async =>
      parseSchedules(LiveUpdatesBridge.scheduledJson().toDartString());

  @override
  Future<void> cancelAllScheduled() async {
    final done = Completer<void>();
    LiveUpdatesBridge.cancelAllScheduled(
      ObjCBlock_ffiVoid.listener(done.complete),
    );
    await done.future;
  }

  @override
  Future<void> cancelScheduled(String key) async {
    final done = Completer<void>();
    LiveUpdatesBridge.cancelScheduled(
      _ns(key),
      completion: ObjCBlock_ffiVoid.listener(done.complete),
    );
    await done.future;
  }
}
