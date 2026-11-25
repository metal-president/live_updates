import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/live_updates_platform_interface.dart';

class FakePlatform extends NoopLiveUpdatesPlatform {
  final calls = <String>[];
  final taps$ = StreamController<String>.broadcast();

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    calls.add('start:${content.title}');
    return 'a1';
  }

  @override
  Future<void> update(String id, LiveUpdateContent content) async =>
      calls.add('update:$id:${content.progress}');

  @override
  Future<void> end(
    String id, {
    LiveUpdateContent? finalContent,
    Duration? dismissAfter,
  }) async => calls.add('end:$id:${dismissAfter?.inSeconds}');

  @override
  Future<List<String>> activeIds() async => ['a1', 'a2'];

  @override
  Future<bool> isPromoted(String id) async => id == 'a1';

  @override
  Stream<String> get taps => taps$.stream;

  @override
  Future<String?> stateForId(String id) async =>
      {'a1': 'stale', 'a2': 'ended'}[id];

  @override
  Future<String?> stateForKey(String key) async =>
      {'order-1': 'dismissed', 'later': 'pending'}[key];
}

void main() {
  late FakePlatform fake;
  setUp(() => LiveUpdatesPlatform.instance = fake = FakePlatform());

  test('start, update and end go to the platform', () async {
    expect(await LiveUpdates.isSupported(), isTrue);
    final u = await LiveUpdates.start(const LiveUpdateContent(title: 'Pizza'));
    expect(u.id, 'a1');
    await u.update(const LiveUpdateContent(title: 'Pizza', progress: .5));
    await u.end(dismissAfter: const Duration(seconds: 3));
    expect(fake.calls, ['start:Pizza', 'update:a1:0.5', 'end:a1:3']);
  });

  test('state and stateOf report the current state', () async {
    final [a1, a2] = await LiveUpdates.active();
    expect(await a1.state(), LiveUpdateState.stale);
    expect(await a2.state(), LiveUpdateState.ended);
    expect(await LiveUpdates.stateOf('order-1'), LiveUpdateState.dismissed);
    // A state the API does not know (such as a scheduled one) is null.
    expect(await LiveUpdates.stateOf('later'), isNull);
    expect(await LiveUpdates.stateOf('order-2'), isNull);
  });

  test('isPromoted asks the platform for that update', () async {
    final [a1, a2] = await LiveUpdates.active();
    expect(await a1.isPromoted(), isTrue);
    expect(await a2.isPromoted(), isFalse);
  });

  test('active returns handles', () async {
    expect((await LiveUpdates.active()).map((u) => u.id), ['a1', 'a2']);
  });

  test('taps are forwarded', () async {
    final next = LiveUpdates.onTap.first;
    fake.taps$.add('/orders/1');
    expect(await next, '/orders/1');
  });

  group('events', eventTests);
  group('keys and actions', keyedTests);
  group('broadcast', broadcastTests);
  group('background handler', backgroundHandlerTests);

  test('noop platform is safe', () async {
    LiveUpdatesPlatform.instance = NoopLiveUpdatesPlatform();
    expect(await LiveUpdates.isSupported(), isFalse);
    final u = await LiveUpdates.start(const LiveUpdateContent(title: 'x'));
    await u.update(const LiveUpdateContent(title: 'y'));
    await u.end();
    expect(await u.isPromoted(), isFalse);
    expect(await LiveUpdates.active(), isEmpty);
  });
}

class EventsPlatform extends NoopLiveUpdatesPlatform {
  final controller = StreamController<(String, String)>.broadcast();
  bool endedAll = false;

  @override
  Stream<(String, String)> get events => controller.stream;

  @override
  Future<void> endAll() async => endedAll = true;
}

void eventTests() {
  late EventsPlatform p;
  setUp(() => LiveUpdatesPlatform.instance = p = EventsPlatform());

  test('states are filtered by id and mapped', () async {
    final update = (await LiveUpdates.active()).firstOrNull;
    expect(update, isNull);
    final started = LiveUpdates.onStarted.first;
    p.controller.add(('x', 'started'));
    final u = await started;
    expect(u.id, 'x');
    final states = u.states.take(2).toList();
    p.controller
      ..add(('y', 'dismissed'))
      ..add(('x', 'stale'))
      ..add(('x', 'pending'))
      ..add(('x', 'dismissed'));
    expect(await states, [LiveUpdateState.stale, LiveUpdateState.dismissed]);
  });

  test('endAll', () async {
    await LiveUpdates.endAll();
    expect(p.endedAll, isTrue);
  });
}

class KeyedPlatform extends NoopLiveUpdatesPlatform {
  final ids = <String, String>{};
  final actionsController = StreamController<(String, String)>.broadcast();
  var counter = 0;

  @override
  Future<String> startOrUpdate(
    String key,
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async => ids.putIfAbsent(key, () => 'id${counter++}');

  @override
  Future<String?> idForKey(String key) async => ids[key];

  @override
  Stream<(String, String)> actions({String? updateId}) => actionsController
      .stream
      .where((e) => updateId == null || e.$1 == updateId);
}

void keyedTests() {
  late KeyedPlatform p;
  setUp(() => LiveUpdatesPlatform.instance = p = KeyedPlatform());

  test('startOrUpdate and find use the key', () async {
    const c = LiveUpdateContent(title: 'T');
    final a = await LiveUpdates.startOrUpdate('k', c);
    final b = await LiveUpdates.startOrUpdate('k', c);
    expect(b, a);
    expect(await LiveUpdates.find('k'), a);
    expect(await LiveUpdates.find('other'), isNull);
  });

  test('actions are routed', () async {
    final u = await LiveUpdates.startOrUpdate(
      'k',
      const LiveUpdateContent(title: 'T'),
    );
    final global = LiveUpdates.onAction.first;
    final own = u.actions.first;
    p.actionsController
      ..add(('other', 'x'))
      ..add((u.id, 'cancel'));
    expect(
      await global,
      const LiveUpdateActionEvent(updateId: 'other', actionId: 'x'),
    );
    expect(await own, 'cancel');
  });
}

class _ChannelPlatform extends NoopLiveUpdatesPlatform {
  String? channel;

  @override
  Future<String> start(
    LiveUpdateContent content, {
    bool pushUpdates = false,
    String? iosChannelId,
  }) async {
    channel = iosChannelId;
    return 'c1';
  }
}

void broadcastTests() {
  late _ChannelPlatform p;
  setUp(() => LiveUpdatesPlatform.instance = p = _ChannelPlatform());

  test('passes the broadcast channel to the platform', () async {
    await LiveUpdates.start(
      const LiveUpdateContent(title: 'Score'),
      iosChannelId: 'Q0g=',
    );
    expect(p.channel, 'Q0g=');
  });

  test('rejects pushUpdates together with a channel', () {
    expect(
      () => LiveUpdates.start(
        const LiveUpdateContent(title: 'Score'),
        pushUpdates: true,
        iosChannelId: 'Q0g=',
      ),
      throwsArgumentError,
    );
    expect(
      () => LiveUpdates.startOrUpdate(
        'k',
        const LiveUpdateContent(title: 'Score'),
        pushUpdates: true,
        iosChannelId: 'Q0g=',
      ),
      throwsArgumentError,
    );
  });
}

void backgroundHandlerTests() {
  test('background handler must be a top-level or static function', () {
    expect(
      () => LiveUpdates.setBackgroundActionHandler((event) async {}),
      throwsArgumentError,
    );
  });
}
