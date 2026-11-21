import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/platform/buffered_broadcast.dart';

void main() {
  test(
    'keeps events until someone listens, including between listeners',
    () async {
      late void Function(int) add;
      var starts = 0;
      final b = BufferedBroadcast<int>((a) {
        starts++;
        add = a;
      });
      final stream = b.stream;
      add(1);
      add(2);
      expect(await stream.take(2).toList(), [1, 2]);
      add(3); // nobody listening now
      expect(await b.stream.first, 3);
      expect(starts, 1);
    },
  );
}
