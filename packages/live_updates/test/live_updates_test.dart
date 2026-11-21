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
  Stream<String> get taps => taps$.stream;
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

  test('noop platform is safe', () async {
    LiveUpdatesPlatform.instance = NoopLiveUpdatesPlatform();
    expect(await LiveUpdates.isSupported(), isFalse);
    final u = await LiveUpdates.start(const LiveUpdateContent(title: 'x'));
    await u.update(const LiveUpdateContent(title: 'y'));
    await u.end();
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
  }) async => ids.putIfAbsent(key, () => 'id${counter++}');

  @override
  Future<String?> idForKey(String key) async => ids[key];

  @override
  Stream<(String, String)> get actions => actionsController.stream;
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
