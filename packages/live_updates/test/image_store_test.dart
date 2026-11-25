import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/image_store.dart';
import 'package:live_updates/src/platform/content_encoder.dart';

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

  testWidgets('keeps images of scheduled content until it is shown', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final later = DateTime.now().add(const Duration(days: 3));
      final name = await store.store(
        LiveUpdateImage.file('example/assets/parcel.png'),
        keepUntil: later,
      );
      final file = File('${dir.path}/$name');
      expect(file.lastModifiedSync().difference(later).inSeconds.abs(), 0);
      // Storing it again for content shown now does not shorten that.
      await store.store(LiveUpdateImage.file('example/assets/parcel.png'));
      expect(file.lastModifiedSync().difference(later).inSeconds.abs(), 0);
      // Another write cleans up, but not this file.
      await store.store(LiveUpdateImage.memory(png, maxDimension: 32));
      expect(file.existsSync(), isTrue);
    });
  });

  testWidgets('the ended image is stored and kept until endAt', (tester) async {
    await tester.runAsync(() async {
      final endAt = DateTime.now().add(const Duration(days: 2));
      final json = jsonDecode(
        await _Encoder(dir).encodeContent(
          LiveUpdateContent(
            title: 'Order',
            endAt: endAt,
            endedContent: const LiveUpdateEndedContent(
              title: 'Done',
              image: LiveUpdateImage.file('example/assets/parcel.png'),
            ),
          ),
        ),
      ) as Map<String, Object?>;
      final name = (json['endedContent']! as Map)['image'] as String;
      expect(name, startsWith(ImageStore.prefix));
      expect(json.containsKey('image'), isFalse);
      final file = File('${dir.path}/$name');
      expect(file.lastModifiedSync().difference(endAt).inSeconds.abs(), 0);
    });
  });

  testWidgets('extra images are stored on iOS only', (tester) async {
    await tester.runAsync(() async {
      const content = LiveUpdateContent(
        title: 'Order',
        ios: IosLiveUpdateOptions(
          extra: {'map': 'text'},
          extraImages: {
            'map': LiveUpdateImage.file('example/assets/parcel.png'),
            'courier': LiveUpdateImage.file(
              'example/assets/parcel.png',
              maxDimension: 64,
            ),
            // Cannot be stored: left out, not the whole content.
            'missing': LiveUpdateImage.file('example/assets/none.png'),
            'missingAsset': LiveUpdateImage.asset('assets/none.png'),
          },
        ),
      );
      final json = jsonDecode(
        await _Encoder(dir, ios: true).encodeContent(content),
      ) as Map<String, Object?>;
      final images = json['extraImages']! as Map;
      expect(images.keys, unorderedEquals(['map', 'courier']));
      for (final name in images.values) {
        expect(name, startsWith(ImageStore.prefix));
        expect(File('${dir.path}/$name').existsSync(), isTrue);
      }
      // Its own key: extra keeps its text values.
      expect(json['extra'], {'map': 'text'});
      final android = jsonDecode(
        await _Encoder(dir).encodeContent(content),
      ) as Map<String, Object?>;
      expect(android.containsKey('extraImages'), isFalse);
      // Without an App Group the pictures are left out, not the content.
      final noGroup = jsonDecode(
        await _Encoder(null, ios: true).encodeContent(content),
      ) as Map<String, Object?>;
      expect(noGroup.containsKey('extraImages'), isFalse);
      expect(noGroup['extra'], {'map': 'text'});
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

  test('rejects non-https network images', () async {
    await expectLater(
      store.store(
        LiveUpdateImage.network(Uri.parse('http://example.com/a.png')),
      ),
      throwsA(isA<LiveUpdateException>()),
    );
  });
}

class _Encoder with ContentEncoder {
  _Encoder(this.dir, {this.ios = false});

  final Directory? dir;
  final bool ios;

  @override
  bool get storesIconAssets => ios;

  @override
  String? get imageDirectory => dir?.path;

  @override
  String get missingImageDirectoryHint => '';
}
