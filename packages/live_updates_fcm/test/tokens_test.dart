import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/live_updates_platform_interface.dart';
import 'package:live_updates_fcm/src/tokens.dart';

class _TokenPlatform extends NoopLiveUpdatesPlatform {
  final pushToStart = StreamController<LiveUpdatePushToken>.broadcast();
  final eventsController = StreamController<(String, String)>.broadcast();
  final activityTokens = <String, StreamController<LiveUpdatePushToken>>{};
  List<String> active = const ['a1'];

  StreamController<LiveUpdatePushToken> tokensOf(String id) =>
      activityTokens.putIfAbsent(id, StreamController.broadcast);

  @override
  Future<List<String>> activeIds() async => active;

  @override
  Stream<LiveUpdatePushToken> get pushToStartTokens => pushToStart.stream;

  @override
  Stream<(String, String)> get events => eventsController.stream;

  @override
  Stream<LiveUpdatePushToken> pushTokens(String id) => tokensOf(id).stream;
}

void main() {
  late _TokenPlatform p;
  setUp(() => LiveUpdatesPlatform.instance = p = _TokenPlatform());

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('merges FCM, push-to-start and activity tokens, deduplicated', () async {
    final fids = StreamController<String>.broadcast();
    final got = <LiveUpdatesToken>[];
    final sub = mergeTokens(installationIds: fids.stream).listen(got.add);
    await pump();

    fids
      ..add('fid-1')
      ..add('fid-1');
    p.pushToStart.add(const LiveUpdatePushToken('aa'));
    p.tokensOf('a1').add(const LiveUpdatePushToken('bb'));
    p.eventsController.add(('a2', 'started'));
    await pump();
    p.tokensOf('a2').add(const LiveUpdatePushToken('cc'));
    await pump();

    expect(got, const [
      LiveUpdatesToken(
        type: LiveUpdatesTokenType.fcmInstallationId,
        value: 'fid-1',
      ),
      LiveUpdatesToken(type: LiveUpdatesTokenType.pushToStart, value: 'aa'),
      LiveUpdatesToken(
        type: LiveUpdatesTokenType.activity,
        value: 'bb',
        updateId: 'a1',
      ),
      LiveUpdatesToken(
        type: LiveUpdatesTokenType.activity,
        value: 'cc',
        updateId: 'a2',
      ),
    ]);
    await sub.cancel();
  });

  test('registration token only when requested', () async {
    final got = <LiveUpdatesToken>[];
    final refresh = StreamController<String>.broadcast();
    final sub = mergeTokens(
      installationIds: const Stream.empty(),
      initialRegistrationToken: () async => 'reg-1',
      registrationTokenRefresh: refresh.stream,
    ).listen(got.add);
    await pump();
    refresh.add('reg-2');
    await pump();
    expect(got.map((t) => (t.type, t.value)), [
      (LiveUpdatesTokenType.fcmRegistrationToken, 'reg-1'),
      (LiveUpdatesTokenType.fcmRegistrationToken, 'reg-2'),
    ]);
    await sub.cancel();
  });

  test('toString does not reveal the token', () {
    const t = LiveUpdatesToken(
      type: LiveUpdatesTokenType.activity,
      value: 'secret',
      updateId: 'a1',
    );
    expect(t.toString(), isNot(contains('secret')));
  });

  test('cancelling stops listening to native sources', () async {
    final sub = mergeTokens(installationIds: const Stream.empty())
        .listen((_) {});
    await pump();
    expect(p.pushToStart.hasListener, isTrue);
    await sub.cancel();
    expect(p.pushToStart.hasListener, isFalse);
  });
}
