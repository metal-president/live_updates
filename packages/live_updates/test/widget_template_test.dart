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
}
