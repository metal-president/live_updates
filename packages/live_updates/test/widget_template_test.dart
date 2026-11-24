import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example widget uses the same LiveUpdatesAttributes as the plugin', () {
    const name = 'LiveUpdatesAttributes.swift';
    final plugin = File('ios/live_updates/Sources/live_updates/$name');
    final example = File('example/ios/LiveUpdatesWidget/$name');
    expect(example.readAsStringSync(), plugin.readAsStringSync());
  });

  test('widget templates use the name placeholder', () {
    final dir = Directory('lib/src/cli/ios_widget');
    for (final f in [
      'LiveActivityWidget.swift.tmpl',
      'WidgetBundle.swift.tmpl',
    ]) {
      expect(File('${dir.path}/$f').readAsStringSync(), contains('{{name}}'));
    }
  });

  test('example widget files match the templates', () {
    const templates = 'lib/src/cli/ios_widget';
    for (final (template, name) in [
      ('Views.swift.tmpl', 'LiveUpdatesViews.swift'),
      ('LiveActivityWidget.swift.tmpl', 'LiveUpdatesWidgetLiveActivity.swift'),
    ]) {
      final expected = File('$templates/$template')
          .readAsStringSync()
          .replaceAll('{{name}}', 'LiveUpdatesWidget');
      expect(
        File('example/ios/LiveUpdatesWidget/$name').readAsStringSync(),
        expected,
        reason: name,
      );
    }
  });

  test('the building blocks show publicContent while private data is '
      'hidden', () {
    final views = File('lib/src/cli/ios_widget/Views.swift.tmpl')
        .readAsStringSync();
    expect(views, contains('struct LiveUpdatesPublicLockScreen'));
    expect(views, contains('struct LiveUpdatesExpandedCenter'));
    expect(views, contains('func liveUpdatesShowsPublic('));
    for (final block in [
      'LiveUpdatesLockScreen',
      'LiveUpdatesExpandedCenter',
      'LiveUpdatesExpandedTrailing',
      'LiveUpdatesExpandedBottom',
      'LiveUpdatesCompactLeading',
      'LiveUpdatesCompactTrailing',
      'LiveUpdatesMinimal',
      'LiveUpdatesIslandIcon',
    ]) {
      final start = views.indexOf('struct $block: View {');
      expect(start, isNot(-1), reason: block);
      final end = views.indexOf('\n}\n', start);
      expect(
        views.substring(start, end),
        contains('liveUpdatesShowsPublic(redactionReasons)'),
        reason: block,
      );
    }
    final layout = File('lib/src/cli/ios_widget/LiveActivityWidget.swift.tmpl')
        .readAsStringSync();
    expect(layout, contains('LiveUpdatesExpandedCenter(state: context.state)'));
    expect(layout, contains('LiveUpdatesPublicLockScreen'));
  });
}
