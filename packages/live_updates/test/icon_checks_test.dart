import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/icon_checks.dart';
import 'package:live_updates/src/platform/content_encoder.dart';

class _Encoder with ContentEncoder {
  @override
  String? get imageDirectory => null;
  @override
  String get missingImageDirectoryHint => '';
}

class _IosEncoderWithoutAppGroup with ContentEncoder {
  @override
  String? get imageDirectory => null;
  @override
  String get missingImageDirectoryHint => 'no App Group';
  @override
  bool get storesIconAssets => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a symbol cannot be the Android small icon', () {
    const content = LiveUpdateContent(
      title: 'T',
      icon: LiveUpdateIcon.symbol('shippingbox'),
    );
    expect(iconWarnings(content, android: true), hasLength(1));
    expect(iconWarnings(content, android: false), isEmpty);
    // An Android icon of its own fixes it.
    expect(
      iconWarnings(
        const LiveUpdateContent(
          title: 'T',
          icon: LiveUpdateIcon.symbol('shippingbox'),
          android: AndroidLiveUpdateOptions(
            smallIcon: LiveUpdateIcon.native('ic_stat'),
          ),
        ),
        android: true,
      ),
      isEmpty,
    );
  });

  test('resource names with extension or type are reported', () {
    for (final name in ['ic_stat.png', '@drawable/ic_stat', 'ic-stat']) {
      expect(
        iconWarnings(
          LiveUpdateContent(title: 'T', icon: LiveUpdateIcon.native(name)),
          android: true,
        ),
        hasLength(1),
        reason: name,
      );
    }
    expect(
      iconWarnings(
        const LiveUpdateContent(
          title: 'T',
          ios: IosLiveUpdateOptions(
            islandIcon: LiveUpdateIcon.native('assets/a.png'),
          ),
        ),
        android: false,
      ),
      hasLength(1),
    );
  });

  test('action icons are checked in the order each platform uses', () {
    const content = LiveUpdateContent(
      title: 'T',
      actions: [
        LiveUpdateAction(
          id: 'a',
          title: 'A',
          icon: LiveUpdateIcon.native('assets/a.png'),
          androidIcon: LiveUpdateIcon.native('@drawable/ic_a'),
        ),
        // Symbols are fine: Android does not show action icons.
        LiveUpdateAction(
          id: 'b',
          title: 'B',
          icon: LiveUpdateIcon.symbol('xmark'),
        ),
      ],
    );
    expect(iconWarnings(content, android: true), [
      contains('LiveUpdateAction("a").androidIcon'),
    ]);
    expect(iconWarnings(content, android: false), [
      contains('LiveUpdateAction("a").icon'),
    ]);
  });

  test('iOS content without asset icons needs no App Group', () async {
    final encoder = _IosEncoderWithoutAppGroup();
    await encoder.encodeContent(
      const LiveUpdateContent(
        title: 'T',
        icon: LiveUpdateIcon.symbol('shippingbox'),
      ),
    );
    await expectLater(
      encoder.encodeContent(
        const LiveUpdateContent(
          title: 'T',
          icon: LiveUpdateIcon.asset('assets/a.png'),
        ),
      ),
      throwsA(isA<LiveUpdateException>()),
    );
  });

  test('folders expand to the image assets under them', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key != 'AssetManifest.bin') return null;
          return const StandardMessageCodec().encodeMessage(<String, Object>{
            'assets/icons/a.png': <Object>[],
            'assets/icons/sub/b.webp': <Object>[],
            'assets/icons/readme.txt': <Object>[],
            'assets/other.png': <Object>[],
          });
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null),
    );
    expect(
      await _Encoder().expandIconAssets(['assets/x.png', 'assets/icons/']),
      ['assets/x.png', 'assets/icons/a.png', 'assets/icons/sub/b.webp'],
    );
  });
}
