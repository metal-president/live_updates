import 'dart:convert';

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

  test('non-finite decimals are left out; const options compile', () {
    const options = AndroidLiveUpdateOptions(
      metrics: [
        AndroidMetric.decimal('Bad', double.nan),
        AndroidMetric.integer('Steps', 1),
      ],
      criticalMetric: 1,
    );
    final json = const LiveUpdateContent(title: 't', android: options).toJson();
    expect(json['metrics'], [
      {'label': 'Bad', 'type': 'decimal', 'value': null, 'fractionDigits': 1},
      {'label': 'Steps', 'type': 'integer', 'value': 1},
    ]);
    expect(jsonEncode(json), isA<String>());
  });

  test('timers are sent as seconds since 1970', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000500);
    expect(
      LiveUpdateContent(
        title: 't',
        timer: LiveUpdateTimer.countdown(at),
      ).toJson()['timerEnd'],
      1700000000.5,
    );
    final json = LiveUpdateContent(
      title: 't',
      timer: LiveUpdateTimer.stopwatch(at),
    ).toJson();
    expect(json['timerStart'], 1700000000.5);
    expect(json.containsKey('timerEnd'), isFalse);
  });

  test('android progress parts, timeout and alert', () {
    final json = const LiveUpdateContent(
      title: 't',
      ios: IosLiveUpdateOptions(
        alert: IosAlert(title: 'a', body: 'b'),
      ),
      android: AndroidLiveUpdateOptions(
        progressSegments: [
          AndroidProgressSegment(1, color: Color(0xFFFF0000)),
          AndroidProgressSegment(
            3,
            semanticStyle: LiveUpdateSemanticStyle.caution,
          ),
        ],
        progressPoints: [AndroidProgressPoint(.5)],
        progressTrackerIcon: 'ic_car',
        timeoutAfter: Duration(minutes: 90),
        alert: true,
      ),
    ).toJson();
    expect(json['progressSegments'], [
      {'length': 1, 'colorArgb': 0xFFFF0000},
      {'length': 3, 'semanticStyle': 'caution'},
    ]);
    expect(json['progressPoints'], [
      {'position': .5},
    ]);
    expect(json['progressTrackerIcon'], 'ic_car');
    expect(json['timeoutAfterMillis'], 5400000);
    expect(json['androidAlert'], isTrue);
    // The iOS alert keeps its own key.
    expect(json['alert'], {'title': 'a', 'body': 'b'});
  });

  test('dynamic island choices', () {
    final json = const LiveUpdateContent(
      title: 't',
      ios: IosLiveUpdateOptions(
        extra: {'gate': 'B12'},
        compactTrailing: IosIslandContent.extra('gate'),
        minimal: IosIslandContent.timer,
      ),
    ).toJson();
    expect(json['compactTrailing'], 'extra:gate');
    expect(json['minimal'], 'timer');
    expect(
      const LiveUpdateContent(title: 't', ios: IosLiveUpdateOptions()).toJson(),
      isNot(contains('compactTrailing')),
    );
  });

  test('ios colors', () {
    final json = const LiveUpdateContent(
      title: 't',
      ios: IosLiveUpdateOptions(
        tint: Color(0xFF3949AB),
        backgroundColor: Color(0xCC000000),
      ),
    ).toJson();
    expect(json['tintArgb'], 0xFF3949AB);
    expect(json['backgroundArgb'], 0xCC000000);
    expect(json.containsKey('colorArgb'), isFalse);
  });
}
