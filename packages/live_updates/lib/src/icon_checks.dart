import 'models.dart';

/// Mistakes in the icons of [content] that would show the default icon on
/// the platform (`android` or iOS), as messages for debug builds.
List<String> iconWarnings(LiveUpdateContent content, {required bool android}) {
  final warnings = <String>[];
  void checkName(String where, LiveUpdateIcon? icon) {
    final name = icon?.name;
    if (name == null) return;
    if (android && !RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
      warnings.add(
        '$where: "$name" is not an Android resource name. Give the drawable '
        'name only (lowercase letters, digits and underscores), without '
        'extension or "@drawable/".',
      );
    } else if (!android && name.contains('/')) {
      warnings.add(
        '$where: "$name" is not an asset catalog image name. For a Flutter '
        'asset use LiveUpdateIcon.asset.',
      );
    }
  }

  if (android) {
    final small = content.android?.smallIcon ?? content.icon;
    if (small?.symbolName != null) {
      warnings.add(
        '${content.android?.smallIcon != null ? 'AndroidLiveUpdateOptions.smallIcon' : 'LiveUpdateContent.icon'} '
        'is a symbol, which Android cannot show; the default icon is used. '
        'Set AndroidLiveUpdateOptions.smallIcon to a drawable or an asset.',
      );
    }
    checkName('AndroidLiveUpdateOptions.smallIcon', content.android?.smallIcon);
    if (content.android?.smallIcon == null) {
      checkName('LiveUpdateContent.icon', content.icon);
    }
    checkName(
      'AndroidLiveUpdateOptions.progressTrackerIcon',
      content.android?.progressTrackerIcon,
    );
    for (final a in content.actions) {
      final where = a.androidIcon != null
          ? 'LiveUpdateAction("${a.id}").androidIcon'
          : 'LiveUpdateAction("${a.id}").icon';
      // A symbol is not reported: Android 7.0+ does not show action icons.
      checkName(where, a.androidIcon ?? a.icon);
    }
  } else {
    checkName('IosLiveUpdateOptions.icon', content.ios?.icon);
    checkName('IosLiveUpdateOptions.islandIcon', content.ios?.islandIcon);
    if (content.ios?.icon == null) {
      checkName('LiveUpdateContent.icon', content.icon);
    }
    for (final a in content.actions) {
      checkName(
        a.iosIcon != null
            ? 'LiveUpdateAction("${a.id}").iosIcon'
            : 'LiveUpdateAction("${a.id}").icon',
        a.iosIcon ?? a.icon,
      );
    }
  }
  return warnings;
}
