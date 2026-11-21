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
            requiresUnlock: true,
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
          'requiresUnlock': true,
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

  test('android metrics and semantic styles', () {
    final end = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final json = LiveUpdateContent(
      title: 't',
      android: AndroidLiveUpdateOptions(
        metrics: [
          const AndroidMetric.integer('Steps', 1979),
          const AndroidMetric.decimal(
            'Distance',
            4.25,
            unit: 'km',
            fractionDigits: 2,
            semanticStyle: LiveUpdateSemanticStyle.caution,
          ),
          const AndroidMetric.text('Gate', 'B12'),
          AndroidMetric.timer('ETA', end),
          const AndroidMetric.pausedStopwatch('Time', Duration(seconds: 90)),
        ],
        criticalMetric: 3,
        bodySemanticStyle: LiveUpdateSemanticStyle.danger,
        progressSemanticStyle: LiveUpdateSemanticStyle.safe,
      ),
    ).toJson();
    expect(json['metrics'], [
      {'label': 'Steps', 'type': 'integer', 'value': 1979},
      {
        'label': 'Distance',
        'type': 'decimal',
        'value': 4.25,
        'unit': 'km',
        'fractionDigits': 2,
        'semanticStyle': 'caution',
      },
      {'label': 'Gate', 'type': 'text', 'value': 'B12'},
      {'label': 'ETA', 'type': 'timer', 'value': 1700000000000},
      {'label': 'Time', 'type': 'pausedStopwatch', 'value': 90000},
    ]);
    expect(json['criticalMetric'], 3);
    expect(json['bodySemanticStyle'], 'danger');
    expect(json['progressSemanticStyle'], 'safe');
  });

  test('no metric keys by default', () {
    final json = const LiveUpdateContent(
      title: 't',
      android: AndroidLiveUpdateOptions(),
    ).toJson();
    expect(json.containsKey('metrics'), isFalse);
    expect(json.containsKey('bodySemanticStyle'), isFalse);
  });
}
