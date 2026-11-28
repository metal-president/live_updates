import 'package:flutter/foundation.dart' show TargetPlatform;

import 'content_check.dart';
import 'models.dart';

const _android = {TargetPlatform.android};
const _ios = {TargetPlatform.iOS};

/// Mistakes in the icons of [content] that would show the default icon on
/// the platform (`android` or iOS), as messages for debug builds.
List<String> iconWarnings(LiveUpdateContent content, {required bool android}) =>
    [for (final i in iconIssues(content, android: android)) i.message];

/// [iconWarnings] as issues ([LiveUpdateContent.check]).
List<LiveUpdateIssue> iconIssues(
  LiveUpdateContent content, {
  required bool android,
}) {
  final issues = <LiveUpdateIssue>[];
  void checkName(String where, LiveUpdateIcon? icon) {
    final name = icon?.name;
    if (name == null) return;
    if (android && !RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
      issues.add(
        LiveUpdateIssue(
          LiveUpdateIssueCode.invalidIconName,
          LiveUpdateIssueSeverity.warning,
          _android,
          '$where: "$name" is not an Android resource name. Give the drawable '
          'name only (lowercase letters, digits and underscores), without '
          'extension or "@drawable/".',
        ),
      );
    } else if (!android && name.contains('/')) {
      issues.add(
        LiveUpdateIssue(
          LiveUpdateIssueCode.invalidIconName,
          LiveUpdateIssueSeverity.warning,
          _ios,
          '$where: "$name" is not an asset catalog image name. For a Flutter '
          'asset use LiveUpdateIcon.asset.',
        ),
      );
    }
  }

  if (android) {
    final small = content.android?.smallIcon ?? content.icon;
    if (small?.symbolName != null) {
      issues.add(
        LiveUpdateIssue(
          LiveUpdateIssueCode.symbolIconOnAndroid,
          LiveUpdateIssueSeverity.warning,
          _android,
          '${content.android?.smallIcon != null ? 'AndroidLiveUpdateOptions.smallIcon' : 'LiveUpdateContent.icon'} '
          'is a symbol, which Android cannot show; the default icon is used. '
          'Set AndroidLiveUpdateOptions.smallIcon to a drawable or an asset.',
        ),
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
  return issues;
}

/// Mistakes in an Android custom layout of [content]
/// ([AndroidLiveUpdateOptions.customLayout]) that Android would only log,
/// as messages for debug builds.
List<String> customLayoutWarnings(LiveUpdateContent content) => [
  for (final i in customLayoutIssues(content)) i.message,
];

/// [customLayoutWarnings] as issues ([LiveUpdateContent.check]).
List<LiveUpdateIssue> customLayoutIssues(LiveUpdateContent content) {
  final layout = content.android?.customLayout;
  if (layout == null) return const [];
  final name = RegExp(r'^[a-z][a-z0-9_]{0,99}$');
  final key = RegExp(r'^[a-z0-9_]{1,64}$');
  LiveUpdateIssue issue(LiveUpdateIssueCode code, String message) =>
      LiveUpdateIssue(code, LiveUpdateIssueSeverity.warning, _android, message);
  return [
    for (final n in [layout.collapsed, ?layout.expanded])
      if (!name.hasMatch(n))
        issue(
          LiveUpdateIssueCode.invalidCustomLayoutName,
          'AndroidCustomLayout: "$n" is not a layout resource name. Give the '
          'file name in res/layout without ".xml" (lowercase letters, '
          'digits and underscores).',
        ),
    for (final k in [...content.extra.keys, ...content.extraImages.keys])
      if (!key.hasMatch(k))
        issue(
          LiveUpdateIssueCode.extraKeyNotShown,
          'extra key "$k" cannot name an Android view (use lowercase letters, '
          'digits and underscores); the custom layout does not show it.',
        ),
    for (final k in content.extra.keys)
      if (k.startsWith('image_'))
        issue(
          LiveUpdateIssueCode.extraKeyNotShown,
          'extra key "$k" starts with image_, which names the views of '
          'extraImages; the custom layout does not show it.',
        ),
  ];
}

/// Why Android will not promote [content] for lack of a title, or `null`.
/// Only content that asks for promotion ([AndroidLiveUpdateMode.liveUpdate],
/// the default) is checked, not content with a custom layout, which is never
/// promoted.
String? titleWarning(LiveUpdateContent content) {
  final mode = content.android?.mode ?? AndroidLiveUpdateMode.liveUpdate;
  if (mode != AndroidLiveUpdateMode.liveUpdate) return null;
  if (content.android?.customLayout != null) return null;
  // Android promotes a title of only spaces too, so only an empty one counts.
  if (content.title.isNotEmpty) return null;
  return 'title is empty; Android only promotes a notification to a Live '
      'Update when it has a title.';
}
