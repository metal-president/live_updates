import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/cli/create.dart';

void main() {
  late Directory root;
  late String android;
  setUp(() {
    root = Directory.systemTemp.createTempSync('lu_ca_');
    android = '${root.path}/android';
    Directory('$android/app/src/main').createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<int> run([List<String> extra = const []]) => create([
    'android',
    '--android-dir',
    android,
    ...extra,
  ], androidTemplates: Directory('lib/src/cli/android_layout'));

  File res(String path) => File('$android/app/src/main/res/$path');

  test('writes both layouts and the keep file', () async {
    expect(await run(), 0);
    final collapsed = res('layout/live_update_custom.xml').readAsStringSync();
    final expanded = res('layout/live_update_custom_expanded.xml')
        .readAsStringSync();
    for (final id in [
      'live_update_title',
      'live_update_body',
      'live_update_progress',
      'live_update_timer',
    ]) {
      expect(collapsed, contains('@+id/$id"'), reason: id);
      expect(expanded, contains('@+id/$id"'), reason: id);
    }
    expect(expanded, contains('@+id/live_update_image"'));
    expect(expanded, contains('@+id/live_update_extra_status"'));
    expect(collapsed, contains("AndroidCustomLayout('live_update_custom'"));
    expect(collapsed, isNot(contains('{{name}}')));
    // No background color, so the system frame's colors show through.
    expect(collapsed, isNot(contains('android:background')));
    expect(expanded, isNot(contains('android:background')));
    expect(
      res('raw/live_updates_keep.xml').readAsStringSync(),
      contains('tools:keep="@layout/live_update_*"'),
    );
  });

  test('keeps your files unless --force', () async {
    expect(await run(), 0);
    res('layout/live_update_custom.xml').writeAsStringSync('<!-- mine -->');
    res('raw/live_updates_keep.xml').writeAsStringSync('<!-- my keep -->');
    expect(await run(), 0);
    expect(
      res('layout/live_update_custom.xml').readAsStringSync(),
      '<!-- mine -->',
    );
    expect(await run(['--force']), 0);
    expect(
      res('layout/live_update_custom.xml').readAsStringSync(),
      contains('live_update_title'),
    );
    // Your version is kept as a copy.
    expect(
      res('layout/live_update_custom.xml.bak').readAsStringSync(),
      '<!-- mine -->',
    );
    // The keep file may list your own layouts: never replaced.
    expect(
      res('raw/live_updates_keep.xml').readAsStringSync(),
      '<!-- my keep -->',
    );
  });

  test('--layout names the files', () async {
    expect(await run(['--layout', 'live_update_courier']), 0);
    expect(res('layout/live_update_courier.xml').existsSync(), isTrue);
    expect(res('layout/live_update_courier_expanded.xml').existsSync(), isTrue);
    expect(
      res('layout/live_update_courier.xml').readAsStringSync(),
      contains("expanded: 'live_update_courier_expanded'"),
    );
  });

  test('rejects names that are not resource names', () async {
    for (final name in ['Courier', '1courier', 'my-layout', '', 'class']) {
      expect(await run(['--layout', name]), 64, reason: name);
    }
  });

  test('needs an Android app project', () async {
    expect(await create(['android', '--android-dir', '${root.path}/none']), 66);
  });

  test('the example layouts are the generated ones', () {
    final dir = Directory('lib/src/cli/android_layout');
    const example = 'example/android/app/src/main/res';
    for (final (template, file) in [
      ('layout.xml.tmpl', 'layout/live_update_custom.xml'),
      ('layout_expanded.xml.tmpl', 'layout/live_update_custom_expanded.xml'),
      ('keep.xml.tmpl', 'raw/live_updates_keep.xml'),
    ]) {
      expect(
        File('$example/$file').readAsStringSync(),
        File('${dir.path}/$template')
            .readAsStringSync()
            .replaceAll('{{name}}', 'live_update_custom'),
        reason: file,
      );
    }
  });

  test('the templates fit what the library binds', () {
    final dir = Directory('lib/src/cli/android_layout');
    final collapsed = File('${dir.path}/layout.xml.tmpl').readAsStringSync();
    // Platform text appearances only: no extra dependency.
    expect(collapsed, isNot(contains('Compat')));
    expect(collapsed, contains('TextAppearance.Material.Notification'));
    expect(collapsed, contains('<Chronometer'));
    expect(collapsed, contains('<ProgressBar'));
  });
}
