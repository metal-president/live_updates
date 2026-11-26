import 'dart:io';

import 'create_android.dart';
import 'create_ios.dart';

const _usage =
    '''
Generates the platform files live_updates needs.

Usage: dart run live_updates:create [ios|android] [options]

  ios       The SwiftUI Live Activity widget extension (ios/<name>).
  android   A custom notification layout pair (android/app/src/main/res/layout).
  (none)    Both, for each platform folder the app has.

Options:
  --force           Also overwrite the files meant for you to edit (iOS:
                    <Name>LiveActivity.swift, <Name>Bundle.swift, Info.plist;
                    Android: the layouts). iOS LiveUpdatesAttributes.swift,
                    LiveUpdatesViews.swift and LiveUpdatesActionIntent.swift
                    are always updated.
  -h, --help        Show this help

iOS options:
  --name <Name>     Extension target name (default: LiveUpdatesWidget)
  --ios-dir <dir>   Flutter iOS directory (default: ios)
  --app-group <id>  App Group shared with the widget for images
                    (default: group.<app bundle id>)
  --no-app-group    Do not set up an App Group
  --no-xcode        Only write the widget sources; do not change
                    Runner.xcodeproj, Info.plist or entitlements

Android options:
  --layout <name>   Layout resource name (default: $defaultAndroidLayout);
                    also writes <name>_expanded
  --android-dir <dir>
                    Flutter Android directory (default: android)
''';

/// Options that take a value, by the platform they belong to (`null`: both).
const _valueOptions = {
  '--name': 'ios',
  '--ios-dir': 'ios',
  '--app-group': 'ios',
  '--layout': 'android',
  '--android-dir': 'android',
};

/// Entry point of `dart run live_updates:create`.
///
/// [iosTemplates] and [androidTemplates] override where the templates are
/// read from (tests run without package URI resolution).
Future<int> create(
  List<String> args, {
  Directory? iosTemplates,
  Directory? androidTemplates,
}) async {
  String? platform;
  var rest = args;
  if (args.isNotEmpty && !args.first.startsWith('-')) {
    platform = args.first;
    rest = args.sublist(1);
    if (platform != 'ios' && platform != 'android') {
      stderr.write('Unknown platform "$platform"\n\n$_usage');
      return 64;
    }
  }
  final values = <String, String>{};
  var force = false;
  var noAppGroup = false;
  var noXcode = false;
  for (var i = 0; i < rest.length; i++) {
    final arg = rest[i];
    if (_valueOptions.containsKey(arg)) {
      if (i + 1 >= rest.length) {
        stderr.write('$arg needs a value\n\n$_usage');
        return 64;
      }
      values[arg] = rest[++i];
      continue;
    }
    switch (arg) {
      case '--force':
        force = true;
      case '--no-app-group':
        noAppGroup = true;
      case '--no-xcode':
        noXcode = true;
      case '-h' || '--help':
        stdout.write(_usage);
        return 0;
      default:
        stderr.write('Unknown option $arg\n\n$_usage');
        return 64;
    }
  }
  // An option of the other platform is a mistake in the command.
  final other = platform == null
      ? null
      : [
          ...values.keys.where((k) => _valueOptions[k] != platform),
          if (platform == 'android' && noAppGroup) '--no-app-group',
          if (platform == 'android' && noXcode) '--no-xcode',
        ];
  if (other != null && other.isNotEmpty) {
    stderr.write(
      '${other.join(', ')} is not an option for $platform\n\n$_usage',
    );
    return 64;
  }

  final iosDir = values['--ios-dir'] ?? 'ios';
  final androidDir = values['--android-dir'] ?? 'android';
  var ios = platform == null || platform == 'ios';
  var android = platform == null || platform == 'android';
  if (platform == null) {
    // Both: only the platforms the app has.
    ios = Directory(iosDir).existsSync();
    android = Directory(androidDir).existsSync();
    if (!ios && !android) {
      stderr.writeln(
        'Neither $iosDir nor $androidDir found. Run from your app root.',
      );
      return 66;
    }
    if (!ios) stdout.writeln('skip   iOS ($iosDir not found)');
    if (!android) stdout.writeln('skip   Android ($androidDir not found)');
  }
  if (ios) {
    final result = await createIos(
      name: values['--name'] ?? 'LiveUpdatesWidget',
      iosDir: iosDir,
      appGroup: noAppGroup ? null : values['--app-group'] ?? 'auto',
      editXcode: !noXcode,
      force: force,
      templates: iosTemplates,
    );
    if (result != 0) return result;
  }
  if (android) {
    if (ios) stdout.writeln();
    return createAndroid(
      layout: values['--layout'] ?? defaultAndroidLayout,
      androidDir: androidDir,
      force: force,
      templates: androidTemplates,
    );
  }
  return 0;
}
