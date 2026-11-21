// Regenerates the Android JNI bindings.
//
//   dart run tool/jnigen.dart
//
// Requires `flutter pub get` and a previous `flutter build apk` of the example
// so Gradle can resolve the compile classpath.
import 'dart:io';

import 'package:jnigen/jnigen.dart';

Future<void> main() async {
  final root = Uri.directory(
    Uri.file(Platform.script.toFilePath()).resolve('..').toFilePath(),
  );
  await JniGenerator(
    input: Input(
      classes: ['com.ttechapp.live_updates.LiveUpdatesBridge'],
      sourcePath: [root.resolve('android/src/main/java/')],
      androidSdk: AndroidSdk(
        addGradleDeps: true,
        androidExample: root.resolve('example/'),
      ),
    ),
    output: Output(
      dart: DartOutput(
        path: root.resolve('lib/src/android/bindings.g.dart'),
        structure: OutputStructure.singleFile,
      ),
    ),
  ).generate();
}
