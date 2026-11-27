import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/live_updates_platform_interface.dart';
import 'package:live_updates/src/platform/default_platform_native.dart';
import 'package:live_updates/src/platform/wire.dart';

class _SettingsPlatform extends NoopLiveUpdatesPlatform {
  var opened = 0;

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }
}

void main() {
  test('openSettings goes to the platform', () async {
    final p = _SettingsPlatform();
    LiveUpdatesPlatform.instance = p;
    expect(await LiveUpdates.openSettings(), isTrue);
    expect(p.opened, 1);
  });

  test('openSettings is false on the no-op platform', () async {
    LiveUpdatesPlatform.instance = NoopLiveUpdatesPlatform();
    expect(await LiveUpdates.openSettings(), isFalse);
  });

  test('an exception without a reason is other', () {
    const e = LiveUpdateException('failed');
    expect(e.reason, LiveUpdateFailure.other);
    expect(e.message, 'failed');
    expect(e.toString(), 'LiveUpdateException: failed');
    expect(
      const LiveUpdateException(
        'off',
        reason: LiveUpdateFailure.disabled,
      ).reason,
      LiveUpdateFailure.disabled,
    );
  });

  test('iOS error codes map to reasons', () {
    expect(failureFromCode(0), LiveUpdateFailure.other);
    expect(failureFromCode(1), LiveUpdateFailure.disabled);
    expect(failureFromCode(2), LiveUpdateFailure.limitReached);
    expect(failureFromCode(3), LiveUpdateFailure.notInForeground);
    expect(failureFromCode(4), LiveUpdateFailure.unsupported);
    expect(failureFromCode(99), LiveUpdateFailure.other);
  });

  test('Android reason names map to reasons', () {
    for (final f in LiveUpdateFailure.values) {
      expect(failureFromName(f.name), f);
    }
    expect(failureFromName('unknown'), LiveUpdateFailure.other);
  });

  test('scheduling below iOS 16.2 fails as unsupported', () async {
    final p = OldIosLiveUpdatesPlatform();
    await expectLater(
      p.schedule('a', const LiveUpdateContent(title: 'A'), at: DateTime(2030)),
      throwsA(
        isA<LiveUpdateException>().having(
          (e) => e.reason,
          'reason',
          LiveUpdateFailure.unsupported,
        ),
      ),
    );
  });
}
