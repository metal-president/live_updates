import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_updates/live_updates.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('start, update, list and end', (tester) async {
    // On Android the runner grants POST_NOTIFICATIONS with adb once the app
    // is installed (see tool/integration_test_android.sh), so poll briefly.
    var supported = await LiveUpdates.isSupported();
    for (var i = 0; !supported && Platform.isAndroid && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      supported = await LiveUpdates.isSupported();
    }
    expect(supported, Platform.isIOS || Platform.isAndroid);
    if (!supported) return;

    final update = await LiveUpdates.start(
      const LiveUpdateContent(title: 'Integration', progress: 0),
    );
    expect(update.id, isNotEmpty);
    expect(await LiveUpdates.active(), contains(update));

    await update.update(
      const LiveUpdateContent(title: 'Integration', progress: .5),
    );
    await update.end(dismissAfter: Duration.zero);
    expect(await LiveUpdates.active(), isNot(contains(update)));
  });

  testWidgets('remote payloads drive Android live updates', (tester) async {
    if (!Platform.isAndroid || !await LiveUpdates.isSupported()) return;
    const id = 'remote-order-1';
    Future<bool> send(String event, [String? content]) =>
        LiveUpdates.handleRemotePayload({
          'live_updates_event': event,
          'live_updates_id': id,
          'live_updates_content': ?content,
        });

    expect(await send('start', '{"title":"Remote","progress":0.1}'), isTrue);
    expect((await LiveUpdates.active()).map((u) => u.id), contains(id));
    expect(await send('update', '{"title":"Remote","progress":0.6}'), isTrue);
    expect(await send('end'), isTrue);
    // A remote update for an update that is no longer shown is ignored.
    expect(await send('update', '{"title":"Remote"}'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect((await LiveUpdates.active()).map((u) => u.id), isNot(contains(id)));
    expect(await LiveUpdates.handleRemotePayload({'other': 'x'}), isFalse);
  });

  testWidgets('onStarted, states and endAll', (tester) async {
    if (!await LiveUpdates.isSupported()) return;
    final started = LiveUpdates.onStarted.first.timeout(
      const Duration(seconds: 5),
    );
    final a = await LiveUpdates.start(const LiveUpdateContent(title: 'A'));
    expect((await started).id, a.id);
    await LiveUpdates.start(const LiveUpdateContent(title: 'B'));
    await LiveUpdates.endAll();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await LiveUpdates.active(), isEmpty);
  });

  testWidgets('scheduling before iOS 26 throws instead of crashing', (
    tester,
  ) async {
    if (!Platform.isIOS || await LiveUpdates.canSchedule()) return;
    // canSchedule is also false on iOS 26+ with Live Activities turned off,
    // where schedule fails as well.
    await expectLater(
      LiveUpdates.schedule(
        'old-ios',
        const LiveUpdateContent(title: 'Later'),
        at: DateTime.now().add(const Duration(hours: 1)),
      ),
      throwsA(isA<LiveUpdateException>()),
    );
    expect(await LiveUpdates.scheduled(), isEmpty);
    await LiveUpdates.cancelScheduled('old-ios');
  });

  testWidgets('schedule, find, reschedule and cancel', (tester) async {
    // iOS 26+ (or Android with notifications allowed).
    if (!await LiveUpdates.canSchedule()) return;
    const key = 'scheduled-order';
    final at = DateTime.now().add(const Duration(hours: 1));
    final s = await LiveUpdates.schedule(
      key,
      const LiveUpdateContent(title: 'Later'),
      at: at,
    );
    final found = await LiveUpdates.findScheduled(key);
    expect(found?.key, key);
    expect(found!.at.difference(at).inSeconds.abs(), lessThanOrEqualTo(1));
    // Not shown before its time.
    expect(await LiveUpdates.find(key), isNull);
    expect(
      (await LiveUpdates.active()).map((u) => u.key),
      isNot(contains(key)),
    );
    // endAll can leave schedules alone.
    await LiveUpdates.endAll(includeScheduled: false);
    expect(await LiveUpdates.findScheduled(key), isNotNull);

    final later = at.add(const Duration(hours: 1));
    final moved = await s.reschedule(
      at: later,
      content: const LiveUpdateContent(title: 'Even later'),
    );
    final again = await LiveUpdates.findScheduled(key);
    expect(again!.at.difference(later).inSeconds.abs(), lessThanOrEqualTo(1));
    expect(await LiveUpdates.scheduled(), hasLength(1));

    await moved.cancel();
    expect(await LiveUpdates.findScheduled(key), isNull);
    // cancelAllScheduled clears every schedule.
    await LiveUpdates.schedule(
      key,
      const LiveUpdateContent(title: 'Later'),
      at: later,
    );
    await LiveUpdates.cancelAllScheduled();
    expect(await LiveUpdates.scheduled(), isEmpty);
    await expectLater(moved.reschedule(), throwsA(isA<LiveUpdateException>()));
  });

  testWidgets('a schedule that is due shows the update now', (tester) async {
    if (!await LiveUpdates.canSchedule()) return;
    const key = 'due-order';
    await LiveUpdates.schedule(
      key,
      const LiveUpdateContent(title: 'Now'),
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final update = await LiveUpdates.find(key);
    expect(update, isNotNull);
    expect(await LiveUpdates.findScheduled(key), isNull);
    await update!.end(dismissAfter: Duration.zero);
  });

  testWidgets('images are stored and shown', (tester) async {
    if (!await LiveUpdates.isSupported()) return;
    final update = await LiveUpdates.start(
      const LiveUpdateContent(
        title: 'With image',
        image: LiveUpdateImage.asset('assets/parcel.png', maxDimension: 64),
      ),
    );
    await update.update(
      const LiveUpdateContent(
        title: 'With image',
        progress: .5,
        image: LiveUpdateImage.asset('assets/parcel.png', maxDimension: 64),
      ),
    );
    await update.end(dismissAfter: Duration.zero);
  });

  testWidgets('icons of every kind, including missing ones, are accepted', (
    tester,
  ) async {
    if (!await LiveUpdates.isSupported()) return;
    await LiveUpdates.preloadIcons(['assets/']);
    final update = await LiveUpdates.start(
      const LiveUpdateContent(
        title: 'With icons',
        progress: .3,
        icon: LiveUpdateIcon.asset('assets/parcel.png'),
        ios: IosLiveUpdateOptions(
          islandIcon: LiveUpdateIcon.symbol('shippingbox.fill'),
          compactLeading: IosIslandContent.icon,
        ),
        android: AndroidLiveUpdateOptions(
          smallIcon: LiveUpdateIcon.native('ic_stat_parcel'),
          progressTrackerIcon: LiveUpdateIcon.asset('assets/parcel.png'),
        ),
        actions: [
          LiveUpdateAction(
            id: 'x',
            title: 'X',
            icon: LiveUpdateIcon.symbol('xmark'),
            androidIcon: LiveUpdateIcon.native('ic_stat_parcel'),
          ),
        ],
      ),
    );
    // Missing icons fall back to the default instead of failing.
    await update.update(
      const LiveUpdateContent(
        title: 'With icons',
        icon: LiveUpdateIcon.native('no_such_icon'),
        ios: IosLiveUpdateOptions(
          islandIcon: LiveUpdateIcon.asset('assets/missing.png'),
        ),
        android: AndroidLiveUpdateOptions(
          smallIcon: LiveUpdateIcon.symbol('xmark'),
        ),
      ),
    );
    await update.end(dismissAfter: Duration.zero);
  });

  testWidgets('startOrUpdate reuses the key and find resolves it', (
    tester,
  ) async {
    if (!await LiveUpdates.isSupported()) return;
    const content = LiveUpdateContent(
      title: 'Keyed',
      actions: [
        LiveUpdateAction(id: 'ok', title: 'OK'),
        LiveUpdateAction(id: 'open', title: 'Open', opensApp: true),
      ],
    );
    final a = await LiveUpdates.startOrUpdate('order-it', content);
    final b = await LiveUpdates.startOrUpdate(
      'order-it',
      content.copyWith(progress: .5),
    );
    expect(b.id, a.id);
    expect((await LiveUpdates.find('order-it'))?.id, a.id);
    expect(
      (await LiveUpdates.active()).where((u) => u.id == a.id),
      hasLength(1),
    );
    await a.end(dismissAfter: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await LiveUpdates.find('order-it'), isNull);
  });

  testWidgets('a key starts again after end, also after an immediate end', (
    tester,
  ) async {
    if (!await LiveUpdates.isSupported()) return;
    const key = 'order-restart-it';
    // end() keeps the ended update visible; startOrUpdate replaces it.
    // Twice, so an update this test ended at once does not block the key.
    for (final dismissAfter in [null, Duration.zero, null]) {
      final a = await LiveUpdates.startOrUpdate(
        key,
        const LiveUpdateContent(title: 'Before'),
      );
      await a.end(dismissAfter: dismissAfter);
      await Future<void>.delayed(const Duration(seconds: 1));
      final b = await LiveUpdates.startOrUpdate(
        key,
        const LiveUpdateContent(title: 'After'),
      );
      expect((await LiveUpdates.find(key))?.id, b.id);
      expect(
        (await LiveUpdates.active()).where((u) => u.key == key),
        hasLength(1),
      );
      await b.end();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await LiveUpdates.endAll(includeScheduled: false);
  });

  testWidgets('state and stateOf follow the lifecycle', (tester) async {
    if (!await LiveUpdates.isSupported()) return;
    const key = 'order-state-it';
    expect(await LiveUpdates.stateOf(key), isNull);
    final u = await LiveUpdates.startOrUpdate(
      key,
      const LiveUpdateContent(title: 'State'),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await u.state(), LiveUpdateState.active);
    expect(await LiveUpdates.stateOf(key), LiveUpdateState.active);
    await u.end();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await u.state(), LiveUpdateState.ended);
    expect(await LiveUpdates.stateOf(key), LiveUpdateState.ended);
    await u.end(dismissAfter: Duration.zero);
    await Future<void>.delayed(const Duration(seconds: 1));
    // iOS may still list the dismissed activity for a moment.
    expect(await u.state(), anyOf(isNull, LiveUpdateState.dismissed));
  });

  testWidgets('Android options do not affect iOS push settings', (
    tester,
  ) async {
    if (!await LiveUpdates.isSupported()) return;
    // A notification channel id must never be read as an iOS broadcast
    // channel (regression test).
    final update = await LiveUpdates.start(
      const LiveUpdateContent(
        title: 'Options',
        android: AndroidLiveUpdateOptions(channelId: 'orders'),
      ),
    );
    await update.end(dismissAfter: Duration.zero);
  });

  testWidgets('keys are reported with live updates', (tester) async {
    if (!await LiveUpdates.isSupported()) return;
    final plain = await LiveUpdates.start(const LiveUpdateContent(title: 'P'));
    final keyed = await LiveUpdates.startOrUpdate(
      'order-key-1',
      const LiveUpdateContent(title: 'K'),
    );
    expect(plain.key, isNull);
    expect(keyed.key, 'order-key-1');
    final byId = {for (final u in await LiveUpdates.active()) u.id: u.key};
    expect(byId[plain.id], isNull);
    expect(byId[keyed.id], 'order-key-1');
    expect((await LiveUpdates.find('order-key-1'))?.key, 'order-key-1');
    await LiveUpdates.endAll();
  });
}
