import 'dart:ui' show Color;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoDynamicColor;

import 'models.dart';

/// Wire format shared with the native bridges.
///
/// Keys match `LiveUpdatesAttributes.ContentState` on iOS (title, body,
/// progress, iconName, route, extra), so the same JSON can be sent as the
/// `content-state` of an APNs Live Activity push.
extension LiveUpdateContentJson on LiveUpdateContent {
  /// Encodes this content for the native side.
  Map<String, Object?> toJson() => {
    'title': title,
    'body': ?body,
    'progress': ?progress,
    'iconName': ?iconName,
    'route': ?route,
    // Seconds since 1970, as the widget reads them.
    if (timer?.start case final s?)
      'timerStart': s.millisecondsSinceEpoch / 1000,
    if (timer?.end case final e?) 'timerEnd': e.millisecondsSinceEpoch / 1000,
    if (actions.isNotEmpty)
      'actions': [
        for (final a in actions)
          {
            'id': a.id,
            'title': a.title,
            if (a.opensApp) 'opensApp': true,
            if (a.requiresUnlock) 'requiresUnlock': true,
            'systemImage': ?a.iosSystemImage,
            'androidIcon': ?a.androidIcon,
          },
      ],
    if (ios case final ios?) ...{
      'extra': ios.extra,
      if (ios.staleDate case final d?)
        'staleDate': d.millisecondsSinceEpoch / 1000,
      'relevanceScore': ?ios.relevanceScore,
      if (ios.alert case final a?)
        'alert': {'title': a.title, 'body': a.body, 'sound': ?a.sound},
      'compactTrailing': ?ios.compactTrailing?.value,
      'minimal': ?ios.minimal?.value,
      ..._colorJson('tint', ios.color),
      ..._colorJson('background', ios.backgroundColor),
    },
    if (android case final a?) ...{
      'channelId': a.channelId,
      'channelName': a.channelName,
      'shortCriticalText': ?a.shortCriticalText,
      'colorArgb': ?a.color?.toARGB32(),
      'whenEpochMillis': ?a.when?.millisecondsSinceEpoch,
      'showChronometer': a.showChronometer,
      if (!a.requestPromotion) 'requestPromotion': false,
      if (a.metrics.isNotEmpty)
        'metrics': [for (final m in a.metrics) m.toJson()],
      'criticalMetric': ?a.criticalMetric,
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
      'progressTrackerIcon': ?a.progressTrackerIcon,
      'timeoutAfterMillis': ?a.timeoutAfter?.inMilliseconds,
      // Not 'alert': that key holds the iOS alert.
      if (a.alert) 'androidAlert': true,
    },
  };
}

extension on AndroidMetric {
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
    if (kind == AndroidMetricKind.decimal) 'fractionDigits': ?fractionDigits,
    'semanticStyle': ?semanticStyle?.name,
  };
}

/// `<name>Argb`, plus `<name>DarkArgb` for a [CupertinoDynamicColor] whose
/// dark variant differs. (Not `colorArgb`: that key is the Android color.)
Map<String, int> _colorJson(String name, Color? color) => switch (color) {
  null => const {},
  final CupertinoDynamicColor c => {
    '${name}Argb': c.color.toARGB32(),
    if (c.darkColor != c.color) '${name}DarkArgb': c.darkColor.toARGB32(),
  },
  final c => {'${name}Argb': c.toARGB32()},
};
