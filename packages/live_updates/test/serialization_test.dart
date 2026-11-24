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
            icon: LiveUpdateIcon.symbol('xmark'),
            androidIcon: LiveUpdateIcon.native('ic_close'),
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
          'icon': {'symbol': 'xmark'},
          'androidIcon': {'native': 'ic_close'},
        },
      ],
    );
  });

  test('android mode is encoded unless it is the default', () {
    Object? mode(AndroidLiveUpdateMode m) => LiveUpdateContent(
      title: 'T',
      android: AndroidLiveUpdateOptions(mode: m),
    ).toJson()['androidMode'];
    expect(mode(AndroidLiveUpdateMode.liveUpdate), isNull);
    expect(mode(AndroidLiveUpdateMode.ongoing), 'ongoing');
    expect(mode(AndroidLiveUpdateMode.classic), 'classic');
  });

  test('android metrics and semantic styles', () {
    final end = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final json = LiveUpdateContent(
      title: 't',
      metrics: [
        const LiveUpdateMetric.integer('Steps', 1979),
        const LiveUpdateMetric.decimal(
          'Distance',
          4.25,
          unit: 'km',
          fractionDigits: 2,
          semanticStyle: LiveUpdateSemanticStyle.caution,
        ),
        const LiveUpdateMetric.text('Gate', 'B12'),
        LiveUpdateMetric.timer('ETA', end),
        const LiveUpdateMetric.pausedStopwatch('Time', Duration(seconds: 90)),
      ],
      criticalMetric: 3,
      android: AndroidLiveUpdateOptions(
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
    const content = LiveUpdateContent(
      title: 't',
      metrics: [
        LiveUpdateMetric.decimal('Bad', double.nan),
        LiveUpdateMetric.integer('Steps', 1),
      ],
      criticalMetric: 1,
    );
    final json = content.toJson();
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
        progressTrackerIcon: LiveUpdateIcon.native('ic_car'),
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
    expect(json['progressTrackerIcon'], {'native': 'ic_car'});
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
        compactLeading: IosIslandContent.timer,
        compactTrailing: IosIslandContent.extra('gate'),
        minimal: IosIslandContent.timer,
      ),
    ).toJson();
    expect(json['compactLeading'], 'timer');
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
        color: Color(0xFF3949AB),
        backgroundColor: Color(0xCC000000),
        foregroundColor: Color(0xFF111111),
      ),
    ).toJson();
    expect(json['tintArgb'], 0xFF3949AB);
    expect(json['backgroundArgb'], 0xCC000000);
    expect(json['foregroundArgb'], 0xFF111111);
    expect(json.containsKey('colorArgb'), isFalse);
  });

  test('steps, journey and layout', () {
    final json = const LiveUpdateContent(
      title: 't',
      steps: LiveUpdateSteps(['Placed', 'Preparing', 'Delivered'], current: 1),
      journey: LiveUpdateJourney(from: 'A', to: 'B', toDetail: '12:30'),
      ios: IosLiveUpdateOptions(layout: IosLiveUpdateLayout.stepper),
    ).toJson();
    expect(json['steps'], {
      'labels': ['Placed', 'Preparing', 'Delivered'],
      'current': 1,
    });
    expect(json['journey'], {'from': 'A', 'to': 'B', 'toDetail': '12:30'});
    expect(json['layout'], 'stepper');
    expect(
      const LiveUpdateContent(
        title: 't',
        ios: IosLiveUpdateOptions(layout: IosLiveUpdateLayout.custom('map')),
      ).toJson()['layout'],
      'map',
    );
  });

  test('icons: one kind each, platform options under their own keys', () {
    final json = const LiveUpdateContent(
      title: 'T',
      icon: LiveUpdateIcon.asset('assets/a.png'),
      ios: IosLiveUpdateOptions(
        icon: LiveUpdateIcon.symbol('shippingbox'),
        islandIcon: LiveUpdateIcon.native('island'),
      ),
      android: AndroidLiveUpdateOptions(
        smallIcon: LiveUpdateIcon.native('ic_stat'),
      ),
    ).toJson();
    expect(json['icon'], {'asset': 'assets/a.png'});
    expect(json['iosIcon'], {'symbol': 'shippingbox'});
    expect(json['islandIcon'], {'native': 'island'});
    expect(json['androidSmallIcon'], {'native': 'ic_stat'});
    expect(json.containsKey('iconName'), isFalse);
  });

  test('icon equality and toString', () {
    expect(const LiveUpdateIcon.native('a'), const LiveUpdateIcon.native('a'));
    expect(
      const LiveUpdateIcon.native('a'),
      isNot(const LiveUpdateIcon.asset('a')),
    );
    expect(
      const LiveUpdateIcon.symbol('a').toString(),
      'LiveUpdateIcon.symbol(a)',
    );
  });
}
