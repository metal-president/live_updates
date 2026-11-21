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
}
