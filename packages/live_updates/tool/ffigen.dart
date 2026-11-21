// Regenerates the iOS FFI bindings.
//
//   dart run tool/ffigen.dart
//
// 1. Emits the Objective-C header of the Swift bridge with `swiftc`.
// 2. Runs FFIgen on that header.
import 'dart:io';

import 'package:ffigen/ffigen.dart';

const _swiftSources = [
  'ios/live_updates/Sources/live_updates/LiveUpdatesAttributes.swift',
  'ios/live_updates/Sources/live_updates/LiveUpdatesBridge.swift',
];

Future<void> main() async {
  final root = Platform.script.resolve('..');
  final header = root.resolve('.dart_tool/live_updates/live_updates-Swift.h');
  Directory.fromUri(header.resolve('.')).createSync(recursive: true);

  final sdk =
      (Process.runSync('xcrun', ['--sdk', 'iphoneos', '--show-sdk-path']).stdout
              as String)
          .trim();
  final swiftc = Process.runSync('xcrun', [
    'swiftc',
    '-sdk',
    sdk,
    '-target',
    'arm64-apple-ios17.2',
    '-module-name',
    'live_updates',
    '-parse-as-library',
    '-typecheck',
    '-emit-objc-header',
    '-emit-objc-header-path',
    header.toFilePath(),
    for (final s in _swiftSources) root.resolve(s).toFilePath(),
  ]);
  if (swiftc.exitCode != 0) {
    stderr.write(swiftc.stderr);
    exit(swiftc.exitCode);
  }

  await FfiGenerator(
    input: Input(entryPoints: [header]),
    output: Output(
      dart: DartOutput(path: root.resolve('lib/src/ios/bindings.g.dart')),
      objectiveCFile: root.resolve(_objcFile),
      preamble: '// ignore_for_file: type=lint',
    ),
    objectiveC: const ObjectiveC(),
    visitors: [
      Visitor(
        objCInterface: (node) =>
            node.isIncluded = node.originalName == 'LiveUpdatesBridge',
        // Foundation enums pulled in transitively; not part of our surface.
        enumClass: (node) => node.silenceWarning = true,
      ),
    ],
  ).generate();

  _postProcessObjC(root.resolve(_objcFile));
}

const _objcFile = 'ios/live_updates/Sources/live_updates_objc/bindings.g.m';

/// Makes the generated trampolines shippable: drops the import of the
/// temporary Swift header (the trampolines do not use it) and appends an
/// anchor function that Swift calls so the static linker keeps this object.
void _postProcessObjC(Uri file) {
  final f = File.fromUri(file);
  final lines = f
      .readAsLinesSync()
      .where((l) => !l.contains('live_updates-Swift.h'))
      .join('\n');
  f.writeAsStringSync(
    '$lines\n\n'
    '#import "live_updates_objc.h"\n'
    'void live_updates_objc_link(void) {}\n',
  );
}
