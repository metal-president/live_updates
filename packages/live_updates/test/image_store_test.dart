import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/image_store.dart';

void main() {
  late Directory dir;
  late ImageStore store;
  final png = File('example/assets/parcel.png').readAsBytesSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lu_images');
    store = ImageStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(int, int)> size(File f) async {
    final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    return (image.width, image.height);
  }

  testWidgets('scales to maxDimension and dedupes', (tester) async {
    await tester.runAsync(() async {
      final name = await store.store(
        LiveUpdateImage.memory(png, maxDimension: 64),
      );
      expect(name, startsWith(ImageStore.prefix));
      expect(await size(File('${dir.path}/$name')), (64, 64));
      expect(
        await store.store(LiveUpdateImage.memory(png, maxDimension: 64)),
        name,
      );
      final bigger = await store.store(
        LiveUpdateImage.memory(png, maxDimension: 512),
      );
      expect(bigger, isNot(name));
      // Never upscales.
      expect(await size(File('${dir.path}/$bigger')), (256, 256));
    });
  });

  testWidgets('removes stale files', (tester) async {
    await tester.runAsync(() async {
      final stale = File('${dir.path}/${ImageStore.prefix}old.png')
        ..writeAsBytesSync([0])
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
      final other = File('${dir.path}/keep.txt')..writeAsStringSync('x');
      await store.store(LiveUpdateImage.file('example/assets/parcel.png'));
      expect(stale.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });
}
