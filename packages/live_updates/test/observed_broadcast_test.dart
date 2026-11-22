import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/platform/observed_broadcast.dart';

void main() {
  late void Function(String) add;
  late List<List<String>> detached;
  late int attaches;
  late ObservedBroadcast<String> b;

  setUp(() {
    detached = [];
    attaches = 0;
    b = ObservedBroadcast<String>(
      attach: (a) {
        attaches++;
        add = a;
      },
      detach: detached.add,
    );
  });

  test('attaches only while someone listens', () async {
    expect(attaches, 0);
    final sub = b.stream().listen((_) {});
    expect(attaches, 1);
    await sub.cancel();
    expect(detached, [<String>[]]);
  });

  test('a filtered listener leaves other events for later listeners', () async {
    final a = <String>[];
    final subA = b.stream((e) => e.startsWith('a')).listen(a.add);
    add('a1');
    add('b1');
    await pumpEventQueue();
    expect(a, ['a1']);
    final all = <String>[];
    final subAll = b.stream().listen(all.add);
    await pumpEventQueue();
    expect(all, ['b1']);
    await subA.cancel();
    await subAll.cancel();
    expect(detached.single, isEmpty);
  });

  test('hands unhandled events back when the last listener leaves', () async {
    final sub = b.stream((e) => e == 'mine').listen((_) {});
    add('other');
    await sub.cancel();
    expect(detached.single, ['other']);
    add('late');
    expect(detached.last, ['late']);
  });
}
