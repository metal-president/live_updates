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

  test('the shared alert has value equality and is part of the content', () {
    const a = LiveUpdateAlert(title: 'Arrived');
    expect(a, const LiveUpdateAlert(title: 'Arrived'));
    expect(a.hashCode, const LiveUpdateAlert(title: 'Arrived').hashCode);
    expect(a, isNot(const LiveUpdateAlert()));
    const c = LiveUpdateContent(title: 'T');
    expect(c.copyWith(alert: a).alert, a);
    expect(c.copyWith(alert: a), isNot(c));
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

  test('endAt and ended content are part of the content', () {
    const e = LiveUpdateEndedContent(title: 'Delivered', body: 'Enjoy');
    expect(e, const LiveUpdateEndedContent(title: 'Delivered', body: 'Enjoy'));
    expect(
      e.hashCode,
      const LiveUpdateEndedContent(title: 'Delivered', body: 'Enjoy').hashCode,
    );
    expect(e, isNot(const LiveUpdateEndedContent(title: 'Delivered')));
    const withIcon = LiveUpdateEndedContent(
      title: 'Delivered',
      icon: LiveUpdateIcon.symbol('checkmark'),
      image: LiveUpdateImage.asset('assets/done.png'),
    );
    expect(
      withIcon,
      const LiveUpdateEndedContent(
        title: 'Delivered',
        icon: LiveUpdateIcon.symbol('checkmark'),
        image: LiveUpdateImage.asset('assets/done.png'),
      ),
    );
    expect(
      withIcon,
      isNot(
        const LiveUpdateEndedContent(
          title: 'Delivered',
          icon: LiveUpdateIcon.symbol('checkmark'),
        ),
      ),
    );
    final at = DateTime(2030);
    final a = LiveUpdateContent(title: 'Order', endAt: at, endedContent: e);
    expect(a, LiveUpdateContent(title: 'Order', endAt: at, endedContent: e));
    expect(a, isNot(LiveUpdateContent(title: 'Order', endAt: at)));
    expect(a, isNot(const LiveUpdateContent(title: 'Order', endedContent: e)));
    expect(a.copyWith(progress: .5).endAt, at);
    expect(a.copyWith(progress: .5).endedContent, e);
    expect(
      const LiveUpdateContent(title: 'x').copyWith(endAt: at, endedContent: e),
      LiveUpdateContent(title: 'x', endAt: at, endedContent: e),
    );
  });

  test('android maxDuration defaults to eight hours', () {
    const options = AndroidLiveUpdateOptions();
    expect(options.maxDuration, const Duration(hours: 8));
    expect(options.removeAtEnd, isFalse);
    expect(options, isNot(const AndroidLiveUpdateOptions(maxDuration: null)));
    expect(options, isNot(const AndroidLiveUpdateOptions(removeAtEnd: true)));
  });
}
