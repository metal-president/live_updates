import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Writes [LiveUpdateImage]s as small PNG files into a directory the native
/// side can read, and returns their file names.
class ImageStore {
  /// Creates a store writing into [directory].
  ImageStore(this.directory);

  /// Target directory (App Group container on iOS, cache dir on Android).
  final Directory directory;

  /// Files not used for this long are deleted on the next write.
  static const maxAge = Duration(days: 1);

  /// Prefix of every file written by the store.
  static const prefix = 'lu_';

  /// Stores [image] and returns the file name relative to [directory].
  Future<String> store(LiveUpdateImage image) async {
    final source = await _load(image);
    final name = '$prefix${_hash(source, image.maxDimension)}.png';
    final file = File('${directory.path}/$name');
    if (file.existsSync()) {
      file.setLastModifiedSync(DateTime.now());
    } else {
      directory.createSync(recursive: true);
      final png = await _scaleToPng(source, image.maxDimension);
      await file.writeAsBytes(png, flush: true);
    }
    _cleanUp(keep: name);
    return name;
  }

  static Future<Uint8List> _load(LiveUpdateImage image) async {
    if (image.bytes case final bytes?) return bytes;
    if (image.filePath case final path?) return File(path).readAsBytes();
    if (image.assetName case final name?) {
      final data = await rootBundle.load(name);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(image.url!)).close();
      if (response.statusCode != HttpStatus.ok) {
        throw LiveUpdateException(
          'Image download failed (${response.statusCode}): ${image.url}',
        );
      }
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  static Future<Uint8List> _scaleToPng(Uint8List source, int max) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(source);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = [
      1.0,
      max / descriptor.width,
      max / descriptor.height,
    ].reduce((a, b) => a < b ? a : b);
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round().clamp(1, max),
      targetHeight: (descriptor.height * scale).round().clamp(1, max),
    );
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (png == null) throw const LiveUpdateException('Image encoding failed');
    return png.buffer.asUint8List();
  }

  /// 64-bit FNV-1a over the bytes and the target size.
  static String _hash(Uint8List bytes, int max) {
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h = (h ^ b) * 0x100000001b3;
    }
    h = (h ^ max) * 0x100000001b3;
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  void _cleanUp({required String keep}) {
    final cutoff = DateTime.now().subtract(maxAge);
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || name == keep) continue;
      try {
        if (entity.lastModifiedSync().isBefore(cutoff)) entity.deleteSync();
      } on FileSystemException {
        // Another process may have removed it; ignore.
      }
    }
  }
}
