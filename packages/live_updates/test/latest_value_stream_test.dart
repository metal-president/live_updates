import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/platform/latest_value_stream.dart';

void main() {
  test('replays the latest value to every new listener', () async {
    late void Function(int) add;
    var starts = 0;
    final s = LatestValueStream<int>((a) {
      starts++;
      add = a;
    });
    final first = s.stream.take(2).toList();
    add(1);
    add(2);
    expect(await first, [1, 2]);
    expect(await s.stream.first, 2); // late listener gets the current value
    final both = Future.wait([
      s.stream.take(2).toList(),
      s.stream.take(2).toList(),
    ]);
    add(3);
    expect(await both, [
      [2, 3],
      [2, 3],
    ]);
    expect(starts, 1);
  });

  test('push tokens do not print their value', () {
    expect(
      const LiveUpdatePushToken('abcdef').toString(),
      isNot(contains('abcdef')),
    );
  });
}
