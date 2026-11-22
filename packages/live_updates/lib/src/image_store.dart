import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show sha256;
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

  /// Largest image download accepted by [LiveUpdateImage.network].
  static const maxDownloadBytes = 10 * 1024 * 1024;

  /// Time allowed for connecting and for each read of a download.
  static const downloadTimeout = Duration(seconds: 15);

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
      // Written under a temporary name and renamed, so native code never
      // reads a partly written file (two stores of one image may overlap).
      final temp = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temp.writeAsBytes(png, flush: true);
      await temp.rename(file.path);
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
    final url = image.url!;
    if (url.scheme != 'https') {
      throw LiveUpdateException('Only https image URLs are allowed: $url');
    }
    final client = HttpClient()..connectionTimeout = downloadTimeout;
    try {
      var target = url;
      HttpClientResponse response;
      // Redirects are followed here, so every hop must be https as well.
      for (var redirects = 0; ; redirects++) {
        final request = await client.getUrl(target).timeout(downloadTimeout);
        request.followRedirects = false;
        response = await request.close().timeout(downloadTimeout);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (!response.isRedirect || location == null) break;
        await response.drain<void>();
        target = target.resolve(location);
        if (redirects >= 3 || target.scheme != 'https') {
          throw LiveUpdateException('Image redirect not allowed: $target');
        }
      }
      if (response.statusCode != HttpStatus.ok) {
        throw LiveUpdateException(
          'Image download failed (${response.statusCode}): $url',
        );
      }
      if (response.contentLength > maxDownloadBytes) {
        throw LiveUpdateException('Image is too large: $url');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(downloadTimeout)) {
        builder.add(chunk);
        if (builder.length > maxDownloadBytes) {
          throw LiveUpdateException('Image is too large: $url');
        }
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw LiveUpdateException('Image download timed out: $url');
    } finally {
      client.close(force: true);
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

  /// SHA-256 over the target size and the bytes (first 128 bits, hex).
  static String _hash(Uint8List bytes, int max) {
    final digest = sha256.convert([...'$max:'.codeUnits, ...bytes]);
    return digest.toString().substring(0, 32);
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
