import 'dart:io';

import 'package:live_updates/src/cli/create.dart';

/// Generates the iOS widget extension and Android notification layouts.
///
/// Usage: `dart run live_updates:create [ios|android] [options]`
Future<void> main(List<String> args) async => exit(await create(args));
