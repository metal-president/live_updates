import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/live_updates_platform_interface.dart';

/// Keeps schedules in memory, like the native bridges.
class SchedulePlatform extends NoopLiveUpdatesPlatform {
  final schedules = <String, (DateTime, String)>{};
  final calls = <String>[];

  @override
  Future<bool> canSchedule() async => true;

  @override
  Future<bool> canScheduleExactly() async => false;

  @override
  Future<bool> openExactAlarmSettings() async {
    calls.add('settings');
    return true;
  }

  @override
  Future<void> schedule(
    String key,
    LiveUpdateContent content, {
    required DateTime at,
    bool pushUpdates = false,
    AndroidScheduleOptions android = const AndroidScheduleOptions(),
  }) async {
    calls.add(
      'schedule:$key:${content.title}:$pushUpdates:${android.exact}:'
      '${android.window.inMinutes}',
    );
    schedules[key] = (at, content.title);
  }

  @override
  Future<void> reschedule(
    String key, {
    required DateTime at,
    LiveUpdateContent? content,
  }) async {
    final old = schedules[key];
    if (old == null) throw const LiveUpdateException('not scheduled');
    calls.add('reschedule:$key:${content?.title}');
    schedules[key] = (at, content?.title ?? old.$2);
  }

  /// Returns times as the native bridges do: local, in milliseconds.
  var roundsTimes = false;

  @override
  Future<List<(String, DateTime)>> scheduled() async => [
    for (final MapEntry(:key, :value) in schedules.entries)
      (
        key,
        roundsTimes
            ? DateTime.fromMillisecondsSinceEpoch(
                value.$1.millisecondsSinceEpoch,
              )
            : value.$1,
      ),
  ];

  @override
  Future<void> cancelAllScheduled() async {
    calls.add('cancelAll');
    schedules.clear();
  }

  @override
  Future<void> cancelScheduled(String key) async {
    calls.add('cancel:$key');
    schedules.remove(key);
  }
}

void main() {
  late SchedulePlatform p;
  setUp(() => LiveUpdatesPlatform.instance = p = SchedulePlatform());
  final t1 = DateTime(2030, 1, 1, 9);
  final t2 = DateTime(2030, 1, 1, 8);

  test('schedule passes the options and returns a handle', () async {
    expect(await LiveUpdates.canSchedule(), isTrue);
    final s = await LiveUpdates.schedule(
      'order',
      const LiveUpdateContent(title: 'Pickup'),
      at: t1,
      pushUpdates: true,
      android: const AndroidScheduleOptions(
        exact: false,
        window: Duration(minutes: 20),
      ),
    );
    expect(s.key, 'order');
    expect(s.at, t1);
    expect(p.calls, ['schedule:order:Pickup:true:false:20']);
  });

  test('the Android options default to an exact alarm', () async {
    await LiveUpdates.schedule(
      'order',
      const LiveUpdateContent(title: 'Pickup'),
      at: t1,
    );
    expect(p.calls, ['schedule:order:Pickup:false:true:10']);
    expect(
      const AndroidScheduleOptions(),
      const AndroidScheduleOptions(exact: true, window: Duration(minutes: 10)),
    );
  });

  test('a negative window is rejected', () async {
    await expectLater(
      LiveUpdates.schedule(
        'order',
        const LiveUpdateContent(title: 'x'),
        at: t1,
        android: const AndroidScheduleOptions(window: Duration(minutes: -1)),
      ),
      throwsArgumentError,
    );
    expect(p.calls, isEmpty);
  });

  test('scheduled lists by time, findScheduled looks up by key', () async {
    await LiveUpdates.schedule(
      'a',
      const LiveUpdateContent(title: 'A'),
      at: t1,
    );
    await LiveUpdates.schedule(
      'b',
      const LiveUpdateContent(title: 'B'),
      at: t2,
    );
    expect((await LiveUpdates.scheduled()).map((s) => s.key), ['b', 'a']);
    final a = await LiveUpdates.findScheduled('a');
    expect(a?.at, t1);
    expect(await LiveUpdates.findScheduled('c'), isNull);
  });

  test('scheduled lists updates due at the same time by key', () async {
    for (final key in ['c', 'a', 'b']) {
      await LiveUpdates.schedule(key, LiveUpdateContent(title: key), at: t1);
    }
    expect((await LiveUpdates.scheduled()).map((s) => s.key), ['a', 'b', 'c']);
  });

  test('handles equal the listed schedule for UTC and microseconds', () async {
    // The platforms keep milliseconds, as local time.
    p.roundsTimes = true;
    final at = DateTime.utc(2030, 1, 1, 9, 0, 0, 123, 456);
    final s = await LiveUpdates.schedule(
      'a',
      const LiveUpdateContent(title: 'A'),
      at: at,
    );
    expect(s, await LiveUpdates.findScheduled('a'));
    expect(s, (await LiveUpdates.scheduled()).single);
    expect(s.at.isUtc, isFalse);
    expect(s.at.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
    final moved = await s.reschedule(at: at.add(const Duration(hours: 1)));
    expect(moved, await LiveUpdates.findScheduled('a'));
  });

  test(
    'reschedule keeps the time unless given and returns a new handle',
    () async {
      final s = await LiveUpdates.schedule(
        'a',
        const LiveUpdateContent(title: 'A'),
        at: t1,
      );
      final moved = await s.reschedule(at: t2);
      expect(moved.at, t2);
      expect(moved, isNot(s));
      expect(p.schedules['a'], (t2, 'A'));
      final changed = await moved.reschedule(
        content: const LiveUpdateContent(title: 'B'),
      );
      expect(changed.at, t2);
      expect(p.schedules['a'], (t2, 'B'));
      expect(p.calls.last, 'reschedule:a:B');
    },
  );

  test('cancel and cancelScheduled remove the schedule', () async {
    final s = await LiveUpdates.schedule(
      'a',
      const LiveUpdateContent(title: 'A'),
      at: t1,
    );
    await s.cancel();
    expect(await LiveUpdates.scheduled(), isEmpty);
    await expectLater(
      s.reschedule(at: t2),
      throwsA(isA<LiveUpdateException>()),
    );
    await LiveUpdates.schedule(
      'b',
      const LiveUpdateContent(title: 'B'),
      at: t1,
    );
    await LiveUpdates.cancelScheduled('b');
    expect(p.calls.where((c) => c.startsWith('cancel')), [
      'cancel:a',
      'cancel:b',
    ]);
  });

  test('cancelAllScheduled removes every schedule', () async {
    await LiveUpdates.schedule(
      'a',
      const LiveUpdateContent(title: 'A'),
      at: t1,
    );
    await LiveUpdates.schedule(
      'b',
      const LiveUpdateContent(title: 'B'),
      at: t2,
    );
    await LiveUpdates.cancelAllScheduled();
    expect(await LiveUpdates.scheduled(), isEmpty);
    expect(p.calls.last, 'cancelAll');
  });

  test('endAll cancels schedules unless told not to', () async {
    await LiveUpdates.schedule(
      'a',
      const LiveUpdateContent(title: 'A'),
      at: t1,
    );
    await LiveUpdates.endAll(includeScheduled: false);
    expect(await LiveUpdates.scheduled(), hasLength(1));
    await LiveUpdates.endAll();
    expect(await LiveUpdates.scheduled(), isEmpty);
    expect(p.calls.where((c) => c == 'cancelAll'), hasLength(1));
  });

  test('exact alarm helpers go to the platform', () async {
    expect(await LiveUpdates.canScheduleExactly(), isFalse);
    expect(await LiveUpdates.openExactAlarmSettings(), isTrue);
    expect(p.calls, ['settings']);
  });

  test(
    'handles compare by key and time and keep the key out of logs',
    () async {
      final a = await LiveUpdates.schedule(
        'order-42',
        const LiveUpdateContent(title: 'x'),
        at: t1,
      );
      expect(a, (await LiveUpdates.findScheduled('order-42'))!);
      expect(
        a.hashCode,
        (await LiveUpdates.findScheduled('order-42'))!.hashCode,
      );
      expect(a.toString(), isNot(contains('order-42')));
    },
  );

  test('the no-op platform cannot schedule but does not fail', () async {
    LiveUpdatesPlatform.instance = NoopLiveUpdatesPlatform();
    expect(await LiveUpdates.canSchedule(), isFalse);
    expect(await LiveUpdates.canScheduleExactly(), isFalse);
    expect(await LiveUpdates.openExactAlarmSettings(), isFalse);
    final s = await LiveUpdates.schedule(
      'a',
      const LiveUpdateContent(title: 'A'),
      at: t1,
    );
    await s.reschedule(at: t2);
    await s.cancel();
    expect(await LiveUpdates.scheduled(), isEmpty);
    expect(await LiveUpdates.findScheduled('a'), isNull);
  });
}
