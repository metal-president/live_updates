import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs the `create ios` Ruby script (lib/src/cli/ios_widget/add_target.rb.tmpl)
/// on a copy of the example's Xcode project.
void main() {
  final hasGem =
      Process.runSync('ruby', ['-e', "require 'xcodeproj'"]).exitCode == 0;

  late Directory root;
  late String project;
  setUp(() {
    root = Directory.systemTemp.createTempSync('lu_at_');
    project = '${root.path}/ios/Runner.xcodeproj';
    Directory(project).createSync(recursive: true);
    for (final f in ['project.pbxproj']) {
      File('example/ios/Runner.xcodeproj/$f').copySync('$project/$f');
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  ProcessResult ruby(String script, List<String> args) {
    final file = File('${root.path}/script.rb')..writeAsStringSync(script);
    return Process.runSync('ruby', [file.path, ...args]);
  }

  ProcessResult addTarget(String name, String extDir) => ruby(
    File('lib/src/cli/ios_widget/add_target.rb.tmpl')
        .readAsStringSync()
        .replaceAll('{{name}}', name),
    [project, name, extDir, ''],
  );

  /// Build settings by configuration name of [target].
  Map<String, Map<String, Object?>> settings(String target) {
    final result = ruby(
      '''
require 'xcodeproj'
require 'json'
t = Xcodeproj::Project.open(ARGV[0]).targets.find { |t| t.name == ARGV[1] }
puts JSON.generate(t.build_configurations.to_h { |c| [c.name, c.build_settings] })
''',
      [project, target],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (jsonDecode(result.stdout as String) as Map).map(
      (k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>()),
    );
  }

  void expectPreviewSettings(Map<String, Map<String, Object?>> s) {
    expect(s['Debug'], containsPair('SWIFT_OPTIMIZATION_LEVEL', '-Onone'));
    expect(
      s['Debug']!['SWIFT_ACTIVE_COMPILATION_CONDITIONS'],
      contains('DEBUG'),
    );
    expect(s['Debug'], containsPair('ENABLE_PREVIEWS', 'YES'));
    for (final c in ['Release', 'Profile']) {
      expect(s[c], isNot(contains('SWIFT_ACTIVE_COMPILATION_CONDITIONS')));
      expect(s[c], isNot(contains('ENABLE_PREVIEWS')));
    }
  }

  test(
    'a new widget target builds Debug unoptimized with DEBUG for previews',
    () {
      final ext = Directory('${root.path}/ios/OtherWidget')..createSync();
      File('${ext.path}/OtherWidgetBundle.swift').writeAsStringSync('');
      final result = addTarget('OtherWidget', ext.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expectPreviewSettings(settings('OtherWidget'));
    },
    skip: hasGem ? false : 'needs Ruby with the xcodeproj gem',
  );

  test('running again adds missing preview settings and keeps set ones', () {
    final strip = ruby(
      '''
require 'xcodeproj'
p = Xcodeproj::Project.open(ARGV[0])
t = p.targets.find { |t| t.name == 'LiveUpdatesWidget' }
t.build_configurations.each do |c|
  %w[SWIFT_OPTIMIZATION_LEVEL SWIFT_ACTIVE_COMPILATION_CONDITIONS ENABLE_PREVIEWS]
    .each { |k| c.build_settings.delete(k) }
end
t.build_configurations.find { |c| c.name == 'Debug' }
  .build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG MINE'
p.save
''',
      [project],
    );
    expect(strip.exitCode, 0, reason: '${strip.stderr}');
    final result = addTarget(
      'LiveUpdatesWidget',
      'example/ios/LiveUpdatesWidget',
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('Xcode previews'));
    final s = settings('LiveUpdatesWidget');
    expectPreviewSettings(s);
    expect(
      s['Debug'],
      containsPair('SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'DEBUG MINE'),
    );
    // Nothing left to set: no message the second time.
    expect(
      addTarget('LiveUpdatesWidget', 'example/ios/LiveUpdatesWidget').stdout,
      isNot(contains('Xcode previews')),
    );
  }, skip: hasGem ? false : 'needs Ruby with the xcodeproj gem');

  test('the example widget has the preview settings', () {
    final text = File('example/ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect('ENABLE_PREVIEWS = YES;'.allMatches(text), hasLength(1));
    expect(
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "\$(inherited) DEBUG";'.allMatches(
        text,
      ),
      hasLength(1),
    );
  });
}
