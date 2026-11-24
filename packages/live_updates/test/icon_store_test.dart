import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/icon_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late IconStore store;
  final png = File('example/assets/parcel.png').readAsBytesSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lu_icons');
    store = IconStore(dir);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = const Utf8Codec().decode(message!.buffer.asUint8List());
          return key == 'assets/parcel.png' ? ByteData.sublistView(png) : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    dir.deleteSync(recursive: true);
  });

  test('file name depends only on the asset name', () {
    // Must match LiveUpdatesImages.iconURL(asset:) in Swift.
    expect(
      IconStore.fileName('assets/parcel.png'),
      matches(RegExp(r'^[0-9a-f]{32}\.png$')),
    );
    expect(
      IconStore.fileName('assets/parcel.png'),
      'e036be2e00f1bd26358db437e998432d.png',
    );
    expect(
      IconStore.fileName('assets/a.png'),
      isNot(IconStore.fileName('assets/b.png')),
    );
  });

  testWidgets('stores a scaled PNG under icons/', (tester) async {
    await tester.runAsync(() async {
      expect(await store.store('assets/parcel.png'), isTrue);
      final file = File(
        '${dir.path}/icons/${IconStore.fileName('assets/parcel.png')}',
      );
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      expect(image.width, LiveUpdateIcon.maxDimension);
      expect(image.height, LiveUpdateIcon.maxDimension);
    });
  });

  testWidgets('reports a missing asset', (tester) async {
    await tester.runAsync(() async {
      expect(await store.store('assets/missing.png'), isFalse);
      expect(Directory('${dir.path}/icons').existsSync(), isFalse);
    });
  });
}
