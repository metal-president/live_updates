import 'dart:convert';
import 'dart:io';

import '../image_store.dart';
import '../models.dart';
import '../serialization.dart';

/// Encodes content for the native bridges, storing its image first.
mixin ContentEncoder {
  /// Where images go, or `null` when images are not available.
  String? get imageDirectory;

  /// Explains a missing [imageDirectory].
  String get missingImageDirectoryHint;

  ImageStore? _store;

  /// JSON for [content], with `image` set to the stored file name.
  Future<String> encodeContent(
    LiveUpdateContent content, [
    Map<String, Object?> extra = const {},
  ]) async {
    final json = {...content.toJson(), ...extra};
    if (content.image case final image?) {
      final store = _store ??= switch (imageDirectory) {
        final dir? => ImageStore(Directory(dir)),
        null => throw LiveUpdateException(missingImageDirectoryHint),
      };
      json['image'] = await store.store(image);
    }
    return jsonEncode(json);
  }
}
