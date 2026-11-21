import 'dart:io';
import 'dart:isolate';

const _usage = '''
Generates the SwiftUI Live Activity widget extension for live_updates.

Usage: dart run live_updates:create_widget [options]

Options:
  --name <Name>     Extension target name (default: LiveUpdatesWidget)
  --ios-dir <dir>   Flutter iOS directory (default: ios)
  --app-group <id>  App Group shared with the widget for images
                    (default: group.<app bundle id>)
  --no-app-group    Do not set up an App Group
  --no-xcode        Only write the Swift sources; skip Xcode and App Group setup
  --force           Overwrite existing generated files
  -h, --help        Show this help
''';

/// Entry point of `dart run live_updates:create_widget`.
Future<int> createWidget(List<String> args) async {
  var name = 'LiveUpdatesWidget';
  var iosDir = 'ios';
  var editXcode = true;
  var force = false;
  String? appGroup = 'auto';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--name':
        name = args[++i];
      case '--ios-dir':
        iosDir = args[++i];
      case '--app-group':
        appGroup = args[++i];
      case '--no-app-group':
        appGroup = null;
      case '--no-xcode':
        editXcode = false;
      case '--force':
        force = true;
      case '-h' || '--help':
        stdout.write(_usage);
        return 0;
      default:
        stderr.write('Unknown option ${args[i]}\n\n$_usage');
        return 64;
    }
  }
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(name)) {
    stderr.writeln('--name must be a Swift identifier, got "$name".');
    return 64;
  }
  final ios = Directory(iosDir);
  final xcodeproj = Directory('$iosDir/Runner.xcodeproj');
  if (!xcodeproj.existsSync()) {
    stderr.writeln('${xcodeproj.path} not found. Run from your app root.');
    return 66;
  }

  final templates = await _templatesDir();
  String render(String file) =>
      File('${templates.path}/$file')
          .readAsStringSync()
          .replaceAll('{{name}}', name);

  final out = Directory('${ios.path}/$name');
  final files = {
    'LiveUpdatesAttributes.swift': _attributesSource(templates),
    '${name}LiveActivity.swift': render('LiveActivityWidget.swift.tmpl'),
    '${name}Bundle.swift': render('WidgetBundle.swift.tmpl'),
    'LiveUpdatesActionIntent.swift': render('ActionIntent.swift.tmpl'),
    'Info.plist': render('Info.plist.tmpl'),
  };
  out.createSync(recursive: true);
  for (final MapEntry(key: file, value: content) in files.entries) {
    final f = File('${out.path}/$file');
    if (f.existsSync() && !force) {
      stdout.writeln('skip   ${f.path} (exists, use --force to overwrite)');
      continue;
    }
    f.writeAsStringSync(content);
    stdout.writeln('write  ${f.path}');
  }

  _enableLiveActivities('${ios.path}/Runner/Info.plist');

  if (editXcode) {
    final script = File(
      '${Directory.systemTemp.path}/live_updates_add_target.rb',
    )..writeAsStringSync(render('add_target.rb.tmpl'));
    final result = Process.runSync('ruby', [
      script.path,
      xcodeproj.path,
      name,
      out.path,
      appGroup ?? '',
    ]);
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr
        ..write(result.stderr)
        ..writeln(
          '\nCould not edit the Xcode project automatically (needs the '
          '"xcodeproj" Ruby gem, bundled with CocoaPods).\n'
          'Add the extension manually: Xcode > File > New > Target > Widget '
          'Extension named "$name" (deployment target 17.2), then replace its '
          'files with the ones in ${out.path}.',
        );
      return 1;
    }
  }
  if (appGroup != null) {
    stdout.writeln(
      '\nImages: register the App Group in your Apple Developer account if '
      'automatic signing does not, and keep it enabled for both targets.',
    );
  }
  stdout.writeln(
    '\nDone. Customize ${out.path}/${name}LiveActivity.swift to change the UI.\n'
    'Keep LiveUpdatesAttributes.swift identical to the plugin\'s copy.',
  );
  return 0;
}

Future<Directory> _templatesDir() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:live_updates/src/cli/ios_widget/'),
  );
  if (uri == null) throw StateError('Cannot locate package:live_updates.');
  return Directory.fromUri(uri);
}

/// The widget needs the exact `LiveUpdatesAttributes` type the plugin uses,
/// so it is copied from the plugin sources instead of a template.
String _attributesSource(Directory templates) => File.fromUri(
  templates.uri.resolve(
    '../../../../ios/live_updates/Sources/live_updates/LiveUpdatesAttributes.swift',
  ),
).readAsStringSync();

void _enableLiveActivities(String plist) {
  if (!File(plist).existsSync()) return;
  _registerTapScheme(plist);
  for (final key in ['NSSupportsLiveActivities']) {
    final read = Process.runSync('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :$key',
      plist,
    ]);
    if (read.exitCode == 0) continue;
    Process.runSync('/usr/libexec/PlistBuddy', [
      '-c',
      'Add :$key bool true',
      plist,
    ]);
    stdout.writeln('update $plist ($key = true)');
  }
}

/// Registers `liveupdates-<bundle id>` so widget taps reach the app.
void _registerTapScheme(String plist) {
  const scheme = r'liveupdates-$(PRODUCT_BUNDLE_IDENTIFIER)';
  final dump = Process.runSync('/usr/libexec/PlistBuddy', [
    '-c',
    'Print :CFBundleURLTypes',
    plist,
  ]);
  if (dump.exitCode == 0 && (dump.stdout as String).contains(scheme)) return;
  final commands = [
    if (dump.exitCode != 0) 'Add :CFBundleURLTypes array',
    'Add :CFBundleURLTypes:0 dict',
    'Add :CFBundleURLTypes:0:CFBundleURLName string live_updates',
    'Add :CFBundleURLTypes:0:CFBundleURLSchemes array',
    'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $scheme',
  ];
  for (final c in commands) {
    Process.runSync('/usr/libexec/PlistBuddy', ['-c', c, plist]);
  }
  stdout.writeln('update $plist (URL scheme $scheme)');
}
