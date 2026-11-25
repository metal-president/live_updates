import 'models.dart';

/// Wire format shared with the native bridges.
///
/// Keys match `LiveUpdatesAttributes.ContentState` on iOS (content, timer,
/// layout data, Dynamic Island and color options), so the same JSON can be
/// sent as the `content-state` of an APNs Live Activity push.
extension LiveUpdateContentJson on LiveUpdateContent {
  /// Encodes this content for the native side.
  Map<String, Object?> toJson() => {
    'title': title,
    'body': ?body,
    // NaN or infinite (such as 0 / 0) would break the JSON; out of range is
    // clamped.
    if (progress case final p? when p.isFinite) 'progress': p.clamp(0, 1),
    'icon': ?icon?.toJson(),
    'route': ?route,
    // Seconds since 1970, as the widget reads them.
    if (timer?.start case final s?)
      'timerStart': s.millisecondsSinceEpoch / 1000,
    if (timer?.end case final e?) 'timerEnd': e.millisecondsSinceEpoch / 1000,
    if (metrics.isNotEmpty) 'metrics': [for (final m in metrics) m.toJson()],
    'criticalMetric': ?criticalMetric,
    if (steps case final s?)
      'steps': {'labels': s.labels, 'current': s.current},
    if (journey case final j?)
      'journey': {
        'from': j.from,
        'to': j.to,
        'fromDetail': ?j.fromDetail,
        'toDetail': ?j.toDetail,
      },
    if (publicContent case final p?)
      'publicContent': {
        'title': p.title,
        'body': ?p.body,
        'keepProgress': p.keepProgress,
        'keepTimer': p.keepTimer,
      },
    // Seconds since 1970, as the timer.
    if (endAt case final e?) 'endAt': e.millisecondsSinceEpoch / 1000,
    if (endedContent case final e?)
      'endedContent': {'title': e.title, 'body': ?e.body},
    // iOS: the stale date, which endAt sets unless the iOS option does.
    if (ios?.staleDate ?? endAt case final d?)
      'staleDate': d.millisecondsSinceEpoch / 1000,
    if (actions.isNotEmpty)
      'actions': [
        for (final a in actions)
          {
            'id': a.id,
            'title': a.title,
            if (a.opensApp) 'opensApp': true,
            if (a.requiresUnlock) 'requiresUnlock': true,
            'icon': ?a.icon?.toJson(),
            'iosIcon': ?a.iosIcon?.toJson(),
            'androidIcon': ?a.androidIcon?.toJson(),
          },
      ],
    if (ios case final ios?) ...{
      'extra': ios.extra,
      'relevanceScore': ?ios.relevanceScore,
      if (ios.alert case final a?)
        'alert': {'title': a.title, 'body': a.body, 'sound': ?a.sound},
      'compactLeading': ?ios.compactLeading?.value,
      'compactTrailing': ?ios.compactTrailing?.value,
      'minimal': ?ios.minimal?.value,
      'layout': ?ios.layout?.value,
      // Not 'colorArgb': that key holds the Android color.
      'tintArgb': ?ios.color?.toARGB32(),
      'backgroundArgb': ?ios.backgroundColor?.toARGB32(),
      'foregroundArgb': ?ios.foregroundColor?.toARGB32(),
      'iosIcon': ?ios.icon?.toJson(),
      'islandIcon': ?ios.islandIcon?.toJson(),
    },
    if (android case final a?) ...{
      'channelId': a.channelId,
      'channelName': a.channelName,
      'androidSmallIcon': ?a.smallIcon?.toJson(),
      'shortCriticalText': ?a.shortCriticalText,
      'colorArgb': ?a.color?.toARGB32(),
      'whenEpochMillis': ?a.when?.millisecondsSinceEpoch,
      'showChronometer': a.showChronometer,
      if (a.mode != AndroidLiveUpdateMode.liveUpdate)
        'androidMode': a.mode.name,
      'bodySemanticStyle': ?a.bodySemanticStyle?.name,
      'progressSemanticStyle': ?a.progressSemanticStyle?.name,
      if (a.progressSegments.isNotEmpty)
        'progressSegments': [
          for (final s in a.progressSegments)
            {
              'length': s.length,
              'colorArgb': ?s.color?.toARGB32(),
              'semanticStyle': ?s.semanticStyle?.name,
            },
        ],
      if (a.progressPoints.isNotEmpty)
        'progressPoints': [
          for (final p in a.progressPoints)
            {
              // jsonEncode rejects NaN; the platform skips a null position.
              'position': p.position.isFinite ? p.position : null,
              'colorArgb': ?p.color?.toARGB32(),
              'semanticStyle': ?p.semanticStyle?.name,
            },
        ],
      'progressTrackerIcon': ?a.progressTrackerIcon?.toJson(),
      'timeoutAfterMillis': ?a.timeoutAfter?.inMilliseconds,
      // Not 'alert': that key holds the iOS alert.
      if (a.alert) 'androidAlert': true,
      if (a.lockScreenVisibility != AndroidLockScreenVisibility.private)
        'androidLockScreenVisibility': a.lockScreenVisibility.name,
      // Absent means the default (8 hours); 0 means no limit.
      if (a.maxDuration != const Duration(hours: 8))
        'maxDurationMillis': switch (a.maxDuration) {
          null => 0,
          // At least 1: 0 stands for no limit.
          final d => d.inMilliseconds < 1 ? 1 : d.inMilliseconds,
        },
      if (a.removeAtEnd) 'removeAtEnd': true,
    },
  };
}

extension on LiveUpdateMetric {
  Map<String, Object?> toJson() => {
    'label': label,
    'type': kind.name,
    'value': switch (value) {
      final DateTime d => d.millisecondsSinceEpoch,
      final Duration d => d.inMilliseconds,
      // jsonEncode rejects NaN and infinity; the platform skips a null value.
      final double d when !d.isFinite => null,
      final v => v,
    },
    'unit': ?unit,
    if (kind == LiveUpdateMetricKind.decimal) 'fractionDigits': ?fractionDigits,
    'semanticStyle': ?semanticStyle?.name,
  };
}

/// Wire format of a [LiveUpdateIcon]: exactly one of `native`, `asset` or
/// `symbol`.
extension LiveUpdateIconJson on LiveUpdateIcon {
  /// Encodes this icon for the native side and for remote payloads.
  Map<String, Object?> toJson() => switch (this) {
    LiveUpdateIcon(:final name?) => {'native': name},
    LiveUpdateIcon(:final assetName?) => {'asset': assetName},
    _ => {'symbol': symbolName},
  };
}
