import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/platform/content_encoder.dart';

class _Encoder with ContentEncoder {
  @override
  String? get imageDirectory => null;
  @override
  String get missingImageDirectoryHint => '';
}

void main() {
  test('an empty title is reported when promotion is asked for', () {
    expect(
      titleWarning(const LiveUpdateContent(title: '')),
      'title is empty; Android only promotes a notification to a Live Update '
      'when it has a title.',
    );
    // Android promotes a title of only spaces.
    expect(titleWarning(const LiveUpdateContent(title: '   ')), isNull);
    expect(
      titleWarning(
        const LiveUpdateContent(title: '', android: AndroidLiveUpdateOptions()),
      ),
      isNotNull,
    );
  });

  test('a title, or a mode without promotion, is not reported', () {
    expect(titleWarning(const LiveUpdateContent(title: 'Order')), isNull);
    for (final mode in [
      AndroidLiveUpdateMode.ongoing,
      AndroidLiveUpdateMode.classic,
    ]) {
      expect(
        titleWarning(
          LiveUpdateContent(
            title: '',
            android: AndroidLiveUpdateOptions(mode: mode),
          ),
        ),
        isNull,
      );
    }
  });

  test('warnIfUntitled prints the warning and does not throw', () {
    final printed = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    addTearDown(() => debugPrint = original);

    final encoder = _Encoder();
    encoder.warnIfUntitled(const LiveUpdateContent(title: 'Order'));
    expect(printed, isEmpty);
    encoder.warnIfUntitled(const LiveUpdateContent(title: ''));
    expect(printed, [
      'live_updates: title is empty; Android only promotes a notification '
          'to a Live Update when it has a title.',
    ]);
  });
}
