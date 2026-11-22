import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/cli/create_widget.dart';

void main() {
  for (final option in ['--name', '--ios-dir', '--app-group']) {
    test('$option without a value is a usage error', () async {
      expect(await createWidget([option]), 64);
    });
  }
}
