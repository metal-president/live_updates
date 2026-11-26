import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/cli/create.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('lu_c_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<int> run(List<String> args) => create(
    args,
    iosTemplates: Directory('lib/src/cli/ios_widget'),
    androidTemplates: Directory('lib/src/cli/android_layout'),
  );

  List<String> dirs() => [
    '--ios-dir',
    '${root.path}/ios',
    '--android-dir',
    '${root.path}/android',
    '--no-xcode',
  ];

  void makeIos() =>
      Directory('${root.path}/ios/Runner.xcodeproj')
          .createSync(recursive: true);
  void makeAndroid() =>
      Directory('${root.path}/android/app/src/main')
          .createSync(recursive: true);

  test('without a platform, generates both', () async {
    makeIos();
    makeAndroid();
    expect(await run(dirs()), 0);
    expect(
      File('${root.path}/ios/LiveUpdatesWidget/LiveUpdatesViews.swift')
          .existsSync(),
      isTrue,
    );
    expect(
      File(
        '${root.path}/android/app/src/main/res/layout/live_update_custom.xml',
      ).existsSync(),
      isTrue,
    );
  });

  test('without a platform, skips a platform folder the app lacks', () async {
    makeAndroid();
    expect(await run(dirs()), 0);
    expect(Directory('${root.path}/ios').existsSync(), isFalse);
    expect(
      File(
        '${root.path}/android/app/src/main/res/layout/live_update_custom.xml',
      ).existsSync(),
      isTrue,
    );
  });

  test('without any platform folder, fails', () async {
    expect(await run(dirs()), 66);
  });

  test(
    'without a platform, a name for a missing platform is an error',
    () async {
      makeIos();
      expect(await run([...dirs(), '--layout', 'live_update_x']), 66);
      expect(
        Directory('${root.path}/ios/LiveUpdatesWidget').existsSync(),
        isFalse,
      );
    },
  );

  test('an android folder without an app project is skipped', () async {
    makeIos();
    Directory('${root.path}/android').createSync();
    expect(await run(dirs()), 0);
  });

  test('the platform may come after the options', () async {
    makeAndroid();
    expect(
      await run([
        '--android-dir',
        '${root.path}/android',
        '--force',
        'android',
      ]),
      0,
    );
  });

  test('usage errors', () async {
    expect(await run(['windows']), 64);
    expect(await run(['--unknown']), 64);
    expect(await run(['--layout']), 64);
    // Options of the other platform.
    expect(await run(['ios', '--layout', 'live_update_x']), 64);
    expect(await run(['android', '--name', 'Widget']), 64);
    expect(await run(['android', '--no-xcode']), 64);
    expect(await run(['ios', 'android']), 64);
    // A flag is not a value.
    expect(await run(['android', '--layout', '--force']), 64);
    expect(await run(['--help']), 0);
  });
}
