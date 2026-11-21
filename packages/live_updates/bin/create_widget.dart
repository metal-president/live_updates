import 'dart:io';

import 'package:live_updates/src/cli/create_widget.dart';

/// Generates the SwiftUI widget extension template for iOS Live Activities.
///
/// Usage: `dart run live_updates:create_widget [--name LiveUpdatesWidget]`
Future<void> main(List<String> args) async => exit(await createWidget(args));
