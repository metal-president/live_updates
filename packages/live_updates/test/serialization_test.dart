import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/serialization.dart';

void main() {
  test('minimal content omits nulls', () {
    expect(const LiveUpdateContent(title: 'T').toJson(), {'title': 'T'});
  });

  test('ios and android options are flattened', () {
    final json = LiveUpdateContent(
      title: 'T',
      body: 'B',
      progress: .5,
      route: '/r',
      ios: IosLiveUpdateOptions(
        staleDate: DateTime.fromMillisecondsSinceEpoch(1500),
        alert: const IosAlert(title: 'a', body: 'b'),
        extra: const {'k': 'v'},
      ),
      android: AndroidLiveUpdateOptions(
        shortCriticalText: 'ETA',
        color: const Color(0xFF112233),
        when: DateTime.fromMillisecondsSinceEpoch(42),
      ),
    ).toJson();
    expect(json, {
      'title': 'T',
      'body': 'B',
      'progress': .5,
      'route': '/r',
      'extra': {'k': 'v'},
      'staleDate': 1.5,
      'alert': {'title': 'a', 'body': 'b'},
      'channelId': 'live_updates',
      'channelName': 'Live updates',
      'shortCriticalText': 'ETA',
      'colorArgb': 0xFF112233,
      'whenEpochMillis': 42,
      'showChronometer': false,
    });
  });

  test('actions are encoded', () {
    expect(
      const LiveUpdateContent(
        title: 'T',
        actions: [
          LiveUpdateAction(id: 'a', title: 'A'),
          LiveUpdateAction(
            id: 'b',
            title: 'B',
            opensApp: true,
            iosSystemImage: 'xmark',
            androidIcon: 'ic_close',
          ),
        ],
      ).toJson()['actions'],
      [
        {'id': 'a', 'title': 'A'},
        {
          'id': 'b',
          'title': 'B',
          'opensApp': true,
          'systemImage': 'xmark',
          'androidIcon': 'ic_close',
        },
      ],
    );
  });

  test('promotion opt-out is encoded', () {
    expect(
      const LiveUpdateContent(
        title: 'T',
        android: AndroidLiveUpdateOptions(requestPromotion: false),
      ).toJson()['requestPromotion'],
      isFalse,
    );
  });
}
