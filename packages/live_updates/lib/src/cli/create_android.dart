import 'dart:io';
import 'dart:isolate';

/// Layout name used when none is given.
const defaultAndroidLayout = 'live_update_custom';

/// Prefix of the layout names that the generated keep file covers.
const _keptPrefix = 'live_update_';

/// `dart run live_updates:create android`: writes a collapsed and an
/// expanded notification layout (`<layout>.xml`, `<layout>_expanded.xml`)
/// to `<androidDir>/app/src/main/res/layout`, and
/// `res/raw/live_updates_keep.xml` so release builds keep them. Existing
/// files are kept unless [force].
///
/// [templates] overrides where the templates are read from (tests run
/// without package URI resolution).
Future<int> createAndroid({
  String layout = defaultAndroidLayout,
  String androidDir = 'android',
  bool force = false,
  Directory? templates,
}) async {
  // Resource names: lowercase letters, digits and underscores; the expanded
  // layout adds "_expanded".
  if (!RegExp(r'^[a-z][a-z0-9_]{0,89}$').hasMatch(layout) ||
      _javaKeywords.contains(layout)) {
    stderr.writeln(
      '--layout must be a resource name (lowercase letters, digits and '
      'underscores, starting with a letter), got "$layout".',
    );
    return 64;
  }
  final res = Directory('$androidDir/app/src/main/res');
  if (!res.parent.existsSync()) {
    stderr.writeln('${res.parent.path} not found. Run from your app root.');
    return 66;
  }
  templates ??= await _templatesDir();
  final dir = templates;
  String render(String file) =>
      File('${dir.path}/$file')
          .readAsStringSync()
          .replaceAll('{{name}}', layout);

  final files = {
    '${res.path}/layout/$layout.xml': render('layout.xml.tmpl'),
    '${res.path}/layout/${layout}_expanded.xml': render(
      'layout_expanded.xml.tmpl',
    ),
  };
  for (final MapEntry(key: path, value: content) in files.entries) {
    final f = File(path);
    if (f.existsSync()) {
      if (!force) {
        stdout.writeln('keep   $path (yours to edit; --force replaces it)');
        continue;
      }
      final old = f.readAsStringSync();
      if (old == content) {
        stdout.writeln('same   $path');
        continue;
      }
      // It may hold your changes: keep a copy.
      File('$path.bak').writeAsStringSync(old);
      stdout.writeln('backup $path.bak');
    }
    f
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    stdout.writeln('write  $path');
  }
  // Shared by every layout: written once, as it may list your own layouts.
  final keep = File('${res.path}/raw/live_updates_keep.xml');
  if (keep.existsSync()) {
    stdout.writeln('keep   ${keep.path}');
  } else {
    keep
      ..createSync(recursive: true)
      ..writeAsStringSync(render('keep.xml.tmpl'));
    stdout.writeln('write  ${keep.path}');
  }
  if (!layout.startsWith(_keptPrefix)) {
    stdout.writeln(
      '\n"$layout" does not start with $_keptPrefix: add '
      '@layout/$layout and @layout/${layout}_expanded to tools:keep in '
      '${keep.path}, or release builds remove them.',
    );
  }
  stdout.writeln(
    '\nDone. Edit the layouts in ${res.path}/layout and show them with\n'
    "AndroidLiveUpdateOptions(customLayout: AndroidCustomLayout('$layout', "
    "expanded: '${layout}_expanded')).",
  );
  return 0;
}

/// Names that resource files cannot have (they become Java fields of R).
const _javaKeywords = {
  'abstract',
  'assert',
  'boolean',
  'break',
  'byte',
  'case',
  'catch',
  'char',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'double',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'float',
  'for',
  'goto',
  'if',
  'implements',
  'import',
  'instanceof',
  'int',
  'interface',
  'long',
  'native',
  'new',
  'null',
  'package',
  'private',
  'protected',
  'public',
  'return',
  'short',
  'static',
  'strictfp',
  'super',
  'switch',
  'synchronized',
  'this',
  'throw',
  'throws',
  'transient',
  'true',
  'try',
  'void',
  'volatile',
  'while',
};

Future<Directory> _templatesDir() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:live_updates/src/cli/android_layout/'),
  );
  if (uri == null) throw StateError('Cannot locate package:live_updates.');
  return Directory.fromUri(uri);
}
