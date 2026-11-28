import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:meta/meta.dart';

import 'icon_checks.dart';
import 'models.dart';
import 'serialization.dart';

/// What a [LiveUpdateIssue] is about. The names are stable: compare them in
/// tests, and handle unknown values with a default branch, as new checks may
/// be added in minor releases.
enum LiveUpdateIssueCode {
  /// iOS: the chosen [IosLiveUpdateOptions.layout] has no data (such as
  /// [IosLiveUpdateLayout.metrics] without [LiveUpdateContent.metrics]), so
  /// the widget shows the standard layout.
  layoutDataMissing,

  /// More than three [LiveUpdateContent.metrics]: only the first three are
  /// shown.
  tooManyMetrics,

  /// Android: [LiveUpdateContent.criticalMetric] is not the index of one of
  /// the shown metrics, so it is ignored.
  criticalMetricOutOfRange,

  /// [LiveUpdateSteps.current] is not the index of a label; the nearest
  /// stage is shown.
  stepsCurrentOutOfRange,

  /// A label of [LiveUpdateContent.steps] is empty, so that stage has no
  /// name.
  emptyStepLabel,

  /// Android 16+: more than 21 stages, for which this package draws a plain
  /// progress bar instead of progress segments.
  tooManySteps,

  /// Android: an empty title, so the notification is not promoted to a Live
  /// Update.
  untitledLiveUpdate,

  /// An icon name in a form the platform cannot use (not an Android resource
  /// name, or an iOS asset catalog name with a path); the default icon is
  /// shown.
  invalidIconName,

  /// Android: a symbol as the small icon, which Android cannot show; the
  /// default icon is shown.
  symbolIconOnAndroid,

  /// Android: a name in [AndroidCustomLayout] that is not a layout resource
  /// name, so the system template is shown.
  invalidCustomLayoutName,

  /// Android: a key of [LiveUpdateContent.extra] or
  /// [LiveUpdateContent.extraImages] that a custom layout cannot show.
  extraKeyNotShown,

  /// Android: a custom layout with [AndroidLiveUpdateMode.liveUpdate];
  /// Android never promotes a custom layout.
  customLayoutNotPromoted,

  /// [LiveUpdateContent.progress] outside 0 to 1 (clamped), or not a finite
  /// number (left out).
  progressOutOfRange,

  /// iOS: the content likely exceeds ActivityKit's 4 KB limit, so starting
  /// or updating the Live Activity fails.
  payloadTooLarge,

  /// A [LiveUpdateImage.maxDimension] that is not positive: the call throws.
  invalidImageSize,

  /// Android: more than three buttons; the system shows three.
  tooManyActions,

  /// Android: [AndroidLiveUpdateOptions.shortCriticalText] of 7 characters
  /// or more, which the status bar chip may cut.
  shortCriticalTextTooLong,

  /// iOS: a Dynamic Island choice ([IosLiveUpdateOptions.compactLeading],
  /// `compactTrailing` or `minimal`) whose data is missing; the island shows
  /// its fallback.
  islandContentMissing,

  /// [LiveUpdateContent.endedContent] that is never shown: there is no
  /// [LiveUpdateContent.endAt] (nor, on iOS, a
  /// [IosLiveUpdateOptions.staleDate]), or Android removes the notification
  /// at that time ([AndroidLiveUpdateOptions.removeAtEnd]).
  endedContentNeverShown,

  /// Remote content (`check(remote: true)`): pictures, which a push or remote
  /// payload cannot add.
  remoteImages,

  /// Remote content: an Android custom layout whose name does not start with
  /// `live_update_`, which remote payloads cannot use.
  remoteLayoutName,

  /// Remote content: an iOS asset icon, which the widget finds only if the
  /// app stored it before ([LiveUpdates.preloadIcons]).
  remoteAssetIcon,
}

/// How much a [LiveUpdateIssue] matters.
enum LiveUpdateIssueSeverity {
  /// Documented platform behavior that may be surprising; nothing is wrong
  /// with the content itself.
  info,

  /// Part of the content is not shown as written.
  warning,

  /// The platform rejects the content, or the call throws.
  error,
}

/// A problem found by [LiveUpdateContent.check].
@immutable
final class LiveUpdateIssue {
  /// Creates an issue.
  const LiveUpdateIssue(this.code, this.severity, this.platforms, this.message);

  /// What the issue is about; stable across releases.
  final LiveUpdateIssueCode code;

  /// How much it matters.
  final LiveUpdateIssueSeverity severity;

  /// Where it applies: [TargetPlatform.iOS], [TargetPlatform.android] or
  /// both.
  final Set<TargetPlatform> platforms;

  /// What happens and how to fix it, in English. The wording may change;
  /// compare [code] in tests.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateIssue &&
      other.code == code &&
      other.severity == severity &&
      other.platforms.length == platforms.length &&
      other.platforms.containsAll(platforms) &&
      other.message == message;

  @override
  int get hashCode =>
      Object.hash(code, severity, Object.hashAllUnordered(platforms), message);

  @override
  String toString() {
    final where = [
      if (platforms.contains(TargetPlatform.iOS)) 'iOS',
      if (platforms.contains(TargetPlatform.android)) 'Android',
    ].join(', ');
    return '${severity.name} [$where] ${code.name}: $message';
  }
}

const _both = {TargetPlatform.iOS, TargetPlatform.android};
const _ios = {TargetPlatform.iOS};
const _android = {TargetPlatform.android};

/// ActivityKit's limit for the attributes and content together, in bytes.
const iosPayloadLimit = 4096;

/// On Android 16+ this package draws one progress segment between each pair
/// of stages, up
/// to this many stages.
const _maxStepSegments = 21;

/// See [LiveUpdateContent.check].
List<LiveUpdateIssue> checkContent(
  LiveUpdateContent content, {
  bool remote = false,
}) {
  final issues = <LiveUpdateIssue>[];
  void add(
    LiveUpdateIssueCode code,
    LiveUpdateIssueSeverity severity,
    Set<TargetPlatform> platforms,
    String message,
  ) => issues.add(LiveUpdateIssue(code, severity, platforms, message));
  const info = LiveUpdateIssueSeverity.info;
  const warning = LiveUpdateIssueSeverity.warning;
  const error = LiveUpdateIssueSeverity.error;

  final android = content.android;
  final mode = android?.mode ?? AndroidLiveUpdateMode.liveUpdate;
  final custom = android?.customLayout;
  final promotable = mode == AndroidLiveUpdateMode.liveUpdate && custom == null;
  final hasProgress = content.progress?.isFinite ?? false;
  final extra = content.mergedExtra;

  // Values.
  if (content.progress case final p? when !p.isFinite || p < 0 || p > 1) {
    add(
      LiveUpdateIssueCode.progressOutOfRange,
      warning,
      _both,
      p.isFinite
          ? 'progress is $p; it must be between 0 and 1 and is clamped.'
          : 'progress is $p, which is not a number between 0 and 1; no '
                'progress is shown.',
    );
  }

  // iOS layout.
  final layout = content.ios?.layout;
  final missing = switch (layout) {
    IosLiveUpdateLayout.timer when content.timer == null => 'timer',
    IosLiveUpdateLayout.metrics when content.metrics.isEmpty => 'metrics',
    IosLiveUpdateLayout.stepper
        when content.steps == null || content.steps!.labels.isEmpty =>
      'steps (with labels)',
    IosLiveUpdateLayout.journey when content.journey == null => 'journey',
    _ => null,
  };
  if (missing != null) {
    add(
      LiveUpdateIssueCode.layoutDataMissing,
      warning,
      _ios,
      'IosLiveUpdateOptions.layout is ${layout!.value}, but the content has '
      'no $missing; the widget shows the standard layout.',
    );
  }

  // Dynamic Island choices.
  for (final (name, choice) in [
    ('compactLeading', content.ios?.compactLeading),
    ('compactTrailing', content.ios?.compactTrailing),
    ('minimal', content.ios?.minimal),
  ]) {
    if (choice == null) continue;
    final value = choice.value;
    final lacks = switch (value) {
      'progress' when !hasProgress => 'no progress',
      'timer' when content.timer == null => 'no timer',
      'body' when content.body == null => 'no body',
      _
          when value.startsWith('extra:') &&
              !extra.containsKey(value.substring('extra:'.length)) =>
        'no extra value "${value.substring('extra:'.length)}"',
      _ => null,
    };
    if (lacks != null) {
      add(
        LiveUpdateIssueCode.islandContentMissing,
        info,
        _ios,
        'IosLiveUpdateOptions.$name is ${choice.value}, but the content has '
        '$lacks; the Dynamic Island shows its fallback.',
      );
    }
  }

  // Metrics.
  if (content.metrics.length > 3) {
    add(
      LiveUpdateIssueCode.tooManyMetrics,
      info,
      _both,
      '${content.metrics.length} metrics; only the first three are shown.',
    );
  }
  if (content.criticalMetric case final i?
      when content.metrics.isNotEmpty &&
          (i < 0 || i >= math.min(content.metrics.length, 3))) {
    add(
      LiveUpdateIssueCode.criticalMetricOutOfRange,
      warning,
      _android,
      'criticalMetric is $i, which is not the index of one of the '
      '${math.min(content.metrics.length, 3)} shown metrics; it is ignored.',
    );
  }

  // Steps.
  if (content.steps case final steps?) {
    final count = steps.labels.length;
    if (count > 0 && (steps.current < 0 || steps.current >= count)) {
      add(
        LiveUpdateIssueCode.stepsCurrentOutOfRange,
        warning,
        _both,
        'steps.current is ${steps.current}, but there are $count labels; the '
        '${steps.current < 0 ? 'first' : 'last'} stage is shown as current.',
      );
    }
    final empty = [
      for (var i = 0; i < count; i++)
        if (steps.labels[i].trim().isEmpty) i,
    ];
    if (empty.isNotEmpty) {
      add(
        LiveUpdateIssueCode.emptyStepLabel,
        warning,
        _both,
        'steps.labels ${empty.join(', ')} ${empty.length == 1 ? 'is' : 'are'} '
        'empty; the stage is shown without a name.',
      );
    }
    if (count > _maxStepSegments &&
        mode != AndroidLiveUpdateMode.classic &&
        custom == null &&
        (android?.progressSegments.isEmpty ?? true) &&
        (android?.progressPoints.isEmpty ?? true)) {
      add(
        LiveUpdateIssueCode.tooManySteps,
        info,
        _android,
        '$count stages; on Android 16+ live_updates draws progress segments '
        'for up to $_maxStepSegments stages and a plain progress bar for '
        'more.',
      );
    }
  }

  // Android presentation.
  if (titleWarning(content) case final w?) {
    add(LiveUpdateIssueCode.untitledLiveUpdate, warning, _android, w);
  }
  if (custom != null && mode == AndroidLiveUpdateMode.liveUpdate) {
    add(
      LiveUpdateIssueCode.customLayoutNotPromoted,
      info,
      _android,
      'Android never promotes a notification with a custom layout to a Live '
      'Update; it shows a regular ongoing notification. Use '
      'AndroidLiveUpdateMode.ongoing to say so.',
    );
  }
  if (content.actions.length > 3) {
    add(
      LiveUpdateIssueCode.tooManyActions,
      info,
      _android,
      '${content.actions.length} buttons; Android shows up to three.',
    );
  }
  if (android?.shortCriticalText case final text?
      when promotable && text.runes.length >= 7) {
    add(
      LiveUpdateIssueCode.shortCriticalTextTooLong,
      info,
      _android,
      'shortCriticalText has ${text.runes.length} characters; the '
      'status bar chip shows it in full only when it is shorter than 7 '
      'characters.',
    );
  }
  issues
    ..addAll(iconIssues(content, android: true))
    ..addAll(iconIssues(content, android: false))
    ..addAll(customLayoutIssues(content));

  // Ended content.
  if (content.endedContent != null) {
    if (content.endAt == null && content.ios?.staleDate == null) {
      add(
        LiveUpdateIssueCode.endedContentNeverShown,
        warning,
        _ios,
        'endedContent is set without endAt (or IosLiveUpdateOptions.'
        'staleDate), so it is never shown.',
      );
    }
    if (content.endAt == null) {
      add(
        LiveUpdateIssueCode.endedContentNeverShown,
        warning,
        _android,
        'endedContent is set without endAt, so it is never shown.',
      );
    } else if (android?.removeAtEnd ?? false) {
      add(
        LiveUpdateIssueCode.endedContentNeverShown,
        warning,
        _android,
        'AndroidLiveUpdateOptions.removeAtEnd removes the notification at '
        'endAt instead of showing endedContent.',
      );
    } else if (content.timer?.end case final countdownEnd?
        when (android?.removeAtCountdownEnd ?? true) &&
            content.endAt!.isAfter(countdownEnd)) {
      add(
        LiveUpdateIssueCode.endedContentNeverShown,
        warning,
        _android,
        'endAt is after the end of the countdown, where Android removes the '
        'notification (AndroidLiveUpdateOptions.removeAtCountdownEnd), so '
        'endedContent is not shown. Set endAt no later than the countdown '
        'end.',
      );
    } else if ((android == null
            ? const Duration(hours: 8)
            : android.maxDuration)
        case final max? when content.endAt!.isAfter(DateTime.now().add(max))) {
      add(
        LiveUpdateIssueCode.endedContentNeverShown,
        warning,
        _android,
        'endAt is more than AndroidLiveUpdateOptions.maxDuration '
        '(${max.inMinutes} minutes) away; a live update started now is '
        'removed before endAt, so endedContent is likely not shown.',
      );
    }
  }

  // Pictures.
  final pictures = <(String, LiveUpdateImage, Set<TargetPlatform>)>[
    if (content.image case final i?) ('image', i, _both),
    for (final MapEntry(:key, :value) in content.extraImages.entries)
      // Android stores extra pictures only for a custom layout.
      ('extraImages["$key"]', value, custom == null ? _ios : _both),
    // ignore: deprecated_member_use_from_same_package
    for (final MapEntry(:key, :value)
        in content.ios?.extraImages.entries ??
            const <MapEntry<String, LiveUpdateImage>>[])
      ('IosLiveUpdateOptions.extraImages["$key"]', value, _ios),
    if (content.endedContent?.image case final i?)
      ('endedContent.image', i, _both),
  ];
  for (final (where, image, platforms) in pictures) {
    if (image.maxDimension <= 0) {
      add(
        LiveUpdateIssueCode.invalidImageSize,
        error,
        platforms,
        '$where: maxDimension must be positive, got ${image.maxDimension}; '
        'the call throws a LiveUpdateException.',
      );
    }
  }

  // Size.
  final size = estimatedIosPayloadBytes(content);
  if (size > iosPayloadLimit) {
    add(
      LiveUpdateIssueCode.payloadTooLarge,
      error,
      _ios,
      'The content takes about $size bytes on iOS; ActivityKit allows '
      '$iosPayloadLimit bytes for the attributes and the content together. '
      'Shorten texts, extra values or buttons.',
    );
  }

  // Remote content.
  if (remote) {
    if (pictures.isNotEmpty) {
      add(
        LiveUpdateIssueCode.remoteImages,
        info,
        pictures.any((p) => p.$3.length == 2) ? _both : _ios,
        'Pictures (${pictures.map((p) => p.$1).join(', ')}) are stored by '
        'the app; a push or remote payload replaces the whole content and '
        'cannot add them.',
      );
    }
    if (custom != null) {
      for (final name in [custom.collapsed, ?custom.expanded]) {
        if (!name.startsWith('live_update_')) {
          add(
            LiveUpdateIssueCode.remoteLayoutName,
            warning,
            _android,
            'Remote payloads can only use layouts whose name starts with '
            'live_update_, not "$name"; '
            '${name == custom.collapsed ? 'the system template is shown' : 'the collapsed layout is used when expanded'}.',
          );
        }
      }
    }
    final assets = {
      ?(content.ios?.icon ?? content.icon)?.assetName,
      ?content.ios?.islandIcon?.assetName,
      ?content.endedContent?.icon?.assetName,
      for (final a in content.actions) ?(a.iosIcon ?? a.icon)?.assetName,
    };
    if (assets.isNotEmpty) {
      add(
        LiveUpdateIssueCode.remoteAssetIcon,
        info,
        _ios,
        'Asset icons (${assets.join(', ')}) reach the iOS widget only if the '
        'app stored them before: call LiveUpdates.preloadIcons with them at '
        'app start.',
      );
    }
  }
  return issues;
}

/// Keys of `LiveUpdatesAttributes.ContentState`, which ActivityKit encodes.
const _contentStateKeys = {
  'title', 'body', 'progress', 'icon', 'iosIcon', 'islandIcon', 'route', //
  'image', 'actions', 'extra', 'extraImages', 'timerStart', 'timerEnd',
  'compactTrailing', 'compactLeading', 'minimal', 'tintArgb',
  'backgroundArgb', 'foregroundArgb', 'layout', 'metrics', 'steps',
  'journey', 'publicContent', 'endedContent',
};

/// The name the image store gives a picture: `lu_`, 32 hex digits, `.png`.
final _storedName = 'lu_${'0' * 32}.png';

/// About how many bytes ActivityKit stores for [content]: the JSON of the
/// fields of `LiveUpdatesAttributes.ContentState`, with stored file names
/// for pictures. The attributes (the key of [LiveUpdates.startOrUpdate])
/// come on top.
@visibleForTesting
int estimatedIosPayloadBytes(LiveUpdateContent content) {
  final json = content.toJson();
  final state = <String, Object?>{
    for (final k in _contentStateKeys)
      if (json.containsKey(k)) k: json[k],
    // Encoded even when empty.
    'actions': [
      for (final a in (json['actions'] as List<Object?>?) ?? const [])
        {
          ...a! as Map<String, Object?>,
          // Encoded even when false.
          'opensApp': (a as Map<String, Object?>)['opensApp'] ?? false,
          'requiresUnlock': a['requiresUnlock'] ?? false,
        }..remove('androidIcon'),
    ],
    'extra': json['extra'] ?? const <String, String>{},
    'extraImages': {
      for (final k in content.mergedExtraImages.keys) k: _storedName,
    },
    'metrics': json['metrics'] ?? const <Object?>[],
    if (content.image != null) 'image': _storedName,
    if (json['endedContent'] case final Map<String, Object?> e)
      'endedContent': {
        ...e,
        if (content.endedContent?.image != null) 'image': _storedName,
      },
  };
  final encoded = jsonEncode(state);
  // JSONEncoder writes "/" as "\/".
  return utf8.encode(encoded).length + '/'.allMatches(encoded).length;
}
