import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Copies [LiveUpdateIcon.asset] icons into the directory shared with the
/// iOS widget extension, under a name derived from the asset name only, so
/// the widget finds them for content sent by a push as well.
///
/// The widget computes the same name (`LiveUpdatesImages.iconURL(asset:)`).
class IconStore {
  /// Creates a store writing into `<directory>/icons`.
  IconStore(Directory directory)
    : directory = Directory('${directory.path}/icons');

  /// Directory of the stored icons. Icons are small and few, so they are
  /// never cleaned up; storing an asset again replaces its file.
  final Directory directory;

  /// Assets written by this process: the first store of an asset after an
  /// app start rewrites it, so changed asset contents reach the widget.
  final _written = <String>{};

  /// File name of the stored [asset]: the first 128 bits of the SHA-256 of
  /// its UTF-8 name, in hex, plus `.png`.
  static String fileName(String asset) =>
      '${sha256.convert(utf8.encode(asset)).toString().substring(0, 32)}.png';

  /// Stores [asset] unless this process already did. Returns `false` when
  /// the asset cannot be loaded or decoded.
  Future<bool> store(String asset) async {
    if (_written.contains(asset)) return true;
    final Uint8List source;
    try {
      final data = await rootBundle.load(asset);
      source = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      return false;
    }
    File? temp;
    try {
      final png = await _scaleToPng(source, LiveUpdateIcon.maxDimension);
      directory.createSync(recursive: true);
      final file = File('${directory.path}/${fileName(asset)}');
      // Written under a temporary name and renamed, so the widget never
      // reads a partly written file.
      temp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temp.writeAsBytes(png, flush: true);
      await temp.rename(file.path);
      temp = null;
      _written.add(asset);
      return true;
    } on Object {
      return false;
    } finally {
      // Not renamed: remove the partial file.
      try {
        if (temp != null && temp.existsSync()) temp.deleteSync();
      } on Object {
        // Best effort.
      }
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
    if (png == null) throw const LiveUpdateException('Icon encoding failed');
    return png.buffer.asUint8List();
  }
}
