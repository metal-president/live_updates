import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';

void main() {
  test('push tokens compare by value', () {
    expect(const LiveUpdatePushToken('ab'), const LiveUpdatePushToken('ab'));
  });

  test('content has value equality and copyWith', () {
    const a = LiveUpdateContent(
      title: 'T',
      progress: .2,
      ios: IosLiveUpdateOptions(extra: {'k': 'v'}),
    );
    expect(
      a,
      const LiveUpdateContent(
        title: 'T',
        progress: .2,
        ios: IosLiveUpdateOptions(extra: {'k': 'v'}),
      ),
    );
    final b = a.copyWith(progress: .8);
    expect(b.progress, .8);
    expect(b.title, 'T');
    expect(b.ios, a.ios);
    expect(b, isNot(a));
  });
}
