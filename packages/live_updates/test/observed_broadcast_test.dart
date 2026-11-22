import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/platform/observed_broadcast.dart';

/// Native side as the iOS and Android bridges implement it: a persistent
/// queue, a filter of update ids, and the background handler for presses
/// Dart does not take.
class FakeNative {
  final queue = <(String, String)>[];
  final background = <(String, String)>[];
  void Function((String, String))? handler;
  Set<String>? filter;

  bool takes((String, String) p) =>
      handler != null && (filter == null || filter!.contains(p.$1));

  void drain() {
    final taken = queue.where(takes).toList();
    queue.removeWhere(takes);
    taken.forEach(handler!);
    runBackground();
  }

  void runBackground() {
    final rest = queue.where((p) => !takes(p)).toList();
    queue.removeWhere((p) => !takes(p));
    background.addAll(rest);
  }

  void press(String update, String action) {
    queue.add((update, action));
    if (handler != null) {
      drain();
    } else {
      runBackground();
    }
  }

  late final broadcast = ObservedBroadcast<(String, String)>(
    keyOf: (e) => e.$1,
    attach: (add, keys) {
      handler = add;
      filter = keys;
      drain();
    },
    setFilter: (keys) {
      filter = keys;
      drain();
    },
    detach: () {
      handler = null;
      filter = null;
      runBackground();
    },
    requeue: (events) {
      queue.addAll(events);
      if (handler != null) {
        drain();
      } else {
        runBackground();
      }
    },
  );
}

void main() {
  late FakeNative native;
  setUp(() => native = FakeNative());

  test('without listeners presses go to the background handler', () {
    native.press('a', 'x');
    expect(native.background, [('a', 'x')]);
  });

  test('onAction takes every press while listened to, then stops', () async {
    final got = <(String, String)>[];
    final sub = native.broadcast.stream().listen(got.add);
    native
      ..press('a', 'x')
      ..press('b', 'y');
    expect(got, [('a', 'x'), ('b', 'y')]);
    await sub.cancel();
    native.press('a', 'z');
    expect(native.background, [('a', 'z')]);
  });

  test(
    'a per-update listener leaves other presses to the background',
    () async {
      final a = <(String, String)>[];
      final sub = native.broadcast.stream('a').listen(a.add);
      native
        ..press('a', 'x')
        ..press('b', 'y');
      expect(a, [('a', 'x')]);
      // Not parked in Dart: B's press reached the background handler.
      expect(native.background, [('b', 'y')]);
      await sub.cancel();
    },
  );

  test('queued presses go to the listener that wants them', () async {
    native.handler = null;
    native.queue.addAll([('a', 'x'), ('b', 'y')]);
    final b = <(String, String)>[];
    final sub = native.broadcast.stream('b').listen(b.add);
    expect(b, [('b', 'y')]);
    expect(native.background, [('a', 'x')]);
    await sub.cancel();
  });

  test('widening the filter hands over newly wanted presses', () async {
    final a = <(String, String)>[];
    final all = <(String, String)>[];
    final subA = native.broadcast.stream('a').listen(a.add);
    final subAll = native.broadcast.stream().listen(all.add);
    native.press('b', 'y');
    expect(all, [('b', 'y')]);
    expect(a, isEmpty);
    await subAll.cancel();
    native.press('b', 'z');
    expect(native.background, [('b', 'z')]);
    await subA.cancel();
  });

  test('a press that arrives after its listener left is handed back', () async {
    final sub = native.broadcast.stream('a').listen((_) {});
    final add = native.handler!;
    await sub.cancel();
    add(('a', 'late'));
    expect(native.background, [('a', 'late')]);
  });
}
