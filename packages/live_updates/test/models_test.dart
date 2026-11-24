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

  test('public content has value equality and is part of the content', () {
    const p = LiveUpdatePublicContent(title: 'Delivery', body: 'On the way');
    expect(
      p,
      const LiveUpdatePublicContent(title: 'Delivery', body: 'On the way'),
    );
    expect(
      p.hashCode,
      const LiveUpdatePublicContent(
        title: 'Delivery',
        body: 'On the way',
      ).hashCode,
    );
    expect(p.keepProgress, isTrue);
    expect(p.keepTimer, isTrue);
    expect(
      p,
      isNot(
        const LiveUpdatePublicContent(
          title: 'Delivery',
          body: 'On the way',
          keepTimer: false,
        ),
      ),
    );
    expect(
      p.toString(),
      'LiveUpdatePublicContent(title: Delivery, body: On the way)',
    );

    const a = LiveUpdateContent(title: 'Order #1234', publicContent: p);
    expect(a, const LiveUpdateContent(title: 'Order #1234', publicContent: p));
    expect(a, isNot(const LiveUpdateContent(title: 'Order #1234')));
    expect(a.copyWith(progress: .5).publicContent, p);
    expect(
      const LiveUpdateContent(title: 'T')
          .copyWith(publicContent: p)
          .publicContent,
      p,
    );
  });

  test('android lock screen visibility defaults to private', () {
    const options = AndroidLiveUpdateOptions();
    expect(options.lockScreenVisibility, AndroidLockScreenVisibility.private);
    expect(
      options,
      isNot(
        const AndroidLiveUpdateOptions(
          lockScreenVisibility: AndroidLockScreenVisibility.secret,
        ),
      ),
    );
  });
}
