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
    if (actions.isNotEmpty)
      'actions': [
        for (final a in actions)
          {
            'id': a.id,
            'title': a.title,
            if (a.opensApp) 'opensApp': true,
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
    },
    if (android case final a?) ...{
      'channelId': a.channelId,
      'channelName': a.channelName,
      'shortCriticalText': ?a.shortCriticalText,
      'colorArgb': ?a.color?.toARGB32(),
      'whenEpochMillis': ?a.when?.millisecondsSinceEpoch,
      'showChronometer': a.showChronometer,
      if (!a.requestPromotion) 'requestPromotion': false,
    },
  };
}
