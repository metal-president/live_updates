import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../icon_checks.dart';
import '../icon_store.dart';
import '../image_store.dart';
import '../models.dart';
import '../serialization.dart';

/// Encodes content for the native bridges, storing its image (and on iOS its
/// asset icons) first.
mixin ContentEncoder {
  /// Where images go, or `null` when images are not available.
  String? get imageDirectory;

  /// Explains a missing [imageDirectory].
  String get missingImageDirectoryHint;

  /// Whether [LiveUpdateIcon.asset] icons are copied into [imageDirectory]
  /// (iOS, where the widget extension cannot read the app's assets). Android
  /// reads them from the app package itself.
  bool get storesIconAssets => false;

  ImageStore? _store;
  IconStore? _iconStore;

  Directory get _directory => switch (imageDirectory) {
    final dir? => Directory(dir),
    null => throw LiveUpdateException(missingImageDirectoryHint),
  };

  /// JSON for [content], with `image` set to the stored file name.
  Future<String> encodeContent(
    LiveUpdateContent content, [
    Map<String, Object?> extra = const {},
  ]) async {
    final json = {...content.toJson(), ...extra};
    assert(() {
      for (final w in iconWarnings(content, android: !storesIconAssets)) {
        debugPrint('live_updates: $w');
      }
      return true;
    }());
    if (content.image case final image?) {
      final store = _store ??= ImageStore(_directory);
      json['image'] = await store.store(image);
    }
    if (storesIconAssets) {
      // Only the icons the widget shows: the iOS option wins over the shared
      // one.
      await storeIconAssets([
        ?(content.ios?.icon ?? content.icon)?.assetName,
        ?content.ios?.islandIcon?.assetName,
        for (final a in content.actions) ?(a.iosIcon ?? a.icon)?.assetName,
      ]);
    }
    return jsonEncode(json);
  }

  /// Warns in debug builds when [content] asks Android for promotion
  /// ([AndroidLiveUpdateMode.liveUpdate]) without a title, which Android
  /// requires to promote a notification. The notification is still posted.
  /// Called for content that is shown as a live update (start and update),
  /// not for final content, which is never promoted.
  void warnIfUntitled(LiveUpdateContent content) {
    assert(() {
      if (titleWarning(content) case final w?) debugPrint('live_updates: $w');
      return true;
    }());
  }

  /// Copies [assets] for the widget extension (see [storesIconAssets]). A
  /// name ending in `/` stands for every image asset under that folder.
  /// Assets that cannot be loaded are reported with a warning; the widget
  /// shows its default icon for them.
  Future<void> storeIconAssets(Iterable<String> assets) async {
    if (!storesIconAssets) return;
    final expanded = await expandIconAssets(assets);
    // Content without asset icons works without an App Group.
    if (expanded.isEmpty) return;
    final store = _iconStore ??= IconStore(_directory);
    for (final asset in expanded) {
      if (!await store.store(asset)) {
        debugPrint(
          'live_updates: icon asset "$asset" could not be loaded; the default '
          'icon is shown instead. Check the name and the assets list in '
          'pubspec.yaml.',
        );
      }
    }
  }

  /// [assets] with each folder (a name ending in `/`) replaced by the image
  /// assets under it, from the app's asset manifest.
  Future<List<String>> expandIconAssets(Iterable<String> assets) async {
    final folders = [
      for (final a in assets)
        if (a.endsWith('/')) a,
    ];
    final result = [
      for (final a in assets)
        if (!a.endsWith('/')) a,
    ];
    if (folders.isEmpty) return result;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final folder in folders) {
      final found = [
        for (final a in manifest.listAssets())
          if (a.startsWith(folder) && _imageExtension.hasMatch(a)) a,
      ];
      if (found.isEmpty) {
        debugPrint('live_updates: no image assets under "$folder".');
      }
      result.addAll(found);
    }
    return result;
  }
}

/// Why Android will not promote [content] for lack of a title, or `null`.
/// Only content that asks for promotion ([AndroidLiveUpdateMode.liveUpdate],
/// the default) is checked.
String? titleWarning(LiveUpdateContent content) {
  final mode = content.android?.mode ?? AndroidLiveUpdateMode.liveUpdate;
  if (mode != AndroidLiveUpdateMode.liveUpdate) return null;
  if (content.title.trim().isNotEmpty) return null;
  return 'title is empty; Android only promotes a notification to a Live '
      'Update when it has a title.';
}

final _imageExtension = RegExp(
  r'\.(png|jpe?g|webp|gif|bmp)$',
  caseSensitive: false,
);
