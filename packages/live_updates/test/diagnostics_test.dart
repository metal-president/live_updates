import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/live_updates_platform_interface.dart';
import 'package:live_updates/src/diagnostics.dart';

typedef _C = LiveUpdateDiagnosticCheck;
typedef _S = LiveUpdateDiagnosticStatus;

class _FakePlatform extends NoopLiveUpdatesPlatform {
  String? channel;

  @override
  Future<LiveUpdateDiagnostics> diagnose({
    String androidChannelId = 'live_updates',
  }) async {
    channel = androidChannelId;
    return androidDiagnostics(_android(), channelId: androidChannelId);
  }
}

Map<String, Object?> _ios({
  String os = '27.1',
  List<Map<String, Object?>> widgets = const [
    {'marked': true, 'minimum': '16.2', 'runs': true},
  ],
  bool supports = true,
  bool? enabled = true,
  String? group = 'group.com.example.app',
  bool reachable = true,
  bool tapScheme = true,
}) => {
  'os': os,
  'widgets': widgets,
  'supportsLiveActivities': supports,
  'activitiesEnabled': ?enabled,
  'appGroup': ?group,
  if (group != null) 'appGroupReachable': reachable,
  'tapScheme': tapScheme,
};

Map<String, Object?> _android({
  bool attached = true,
  int sdk = 36,
  String release = '16',
  bool enabled = true,
  bool? granted = true,
  Map<String, Object?>? channel = const {
    'exists': true,
    'importance': 3,
    'groupBlocked': false,
  },
  bool promotedDeclared = true,
  bool canPostPromoted = true,
  bool exactDeclared = true,
  bool canExact = true,
  String defaultIcon = 'valid',
}) => {
  'attached': attached,
  'sdk': sdk,
  'release': release,
  'notificationsEnabled': enabled,
  'postNotificationsGranted': ?granted,
  'channel': ?channel,
  'promotedDeclared': promotedDeclared,
  'canPostPromoted': canPostPromoted,
  'exactAlarmDeclared': exactDeclared,
  'canScheduleExactly': canExact,
  'defaultIcon': defaultIcon,
};

Map<_C, _S> _statuses(LiveUpdateDiagnostics d) => {
  for (final i in d.items) i.check: i.status,
};

void main() {
  test('unsupported platforms say so', () async {
    LiveUpdatesPlatform.instance = NoopLiveUpdatesPlatform();
    final d = await LiveUpdates.diagnose();
    expect(d.platform, isNull);
    expect(d.items.single.check, _C.platform);
    expect(d.hasNoProblems, isFalse);
    expect(d.toString(), contains('unsupported platform'));
  });

  test('diagnose passes the channel to the platform', () async {
    final p = _FakePlatform();
    LiveUpdatesPlatform.instance = p;
    final d = await LiveUpdates.diagnose(androidChannelId: 'orders');
    expect(p.channel, 'orders');
    expect(d[_C.notificationChannel]!.message, contains('"orders"'));
    await LiveUpdates.diagnose();
    expect(p.channel, 'live_updates');
  });

  group('iOS', () {
    test('a complete setup on a current iOS', () {
      final d = iosDiagnostics(_ios());
      expect(d.platform, TargetPlatform.iOS);
      expect(d.osVersion, '27.1');
      expect(d.hasNoProblems, isTrue);
      expect(d.warnings, isEmpty);
      expect(_statuses(d).keys, [
        _C.osVersion,
        _C.widgetExtension,
        _C.supportsLiveActivities,
        _C.liveActivitiesEnabled,
        _C.appGroup,
        _C.tapUrlScheme,
        _C.buttons,
        _C.pushToStart,
        _C.scheduling,
      ]);
      expect(_statuses(d).values.toSet(), {_S.ok});
    });

    test('below 16.2 nothing is shown', () {
      final d = iosDiagnostics(_ios(os: '16.1.0', enabled: null));
      expect(_statuses(d), containsPair(_C.osVersion, _S.problem));
      expect(
        _statuses(d),
        containsPair(_C.liveActivitiesEnabled, _S.notApplicable),
      );
      for (final c in [_C.buttons, _C.pushToStart, _C.scheduling]) {
        expect(_statuses(d), containsPair(c, _S.notApplicable));
      }
    });

    test(
      'feature minimums: buttons 17.0, push-to-start 17.2, scheduling 26',
      () {
        Map<_C, _S> at(String os) => _statuses(iosDiagnostics(_ios(os: os)));
        expect(at('16.4'), containsPair(_C.buttons, _S.warning));
        expect(at('17.0'), containsPair(_C.buttons, _S.ok));
        expect(at('17.1'), containsPair(_C.pushToStart, _S.warning));
        expect(at('17.2'), containsPair(_C.pushToStart, _S.ok));
        expect(at('18.6'), containsPair(_C.scheduling, _S.warning));
        expect(at('26.0'), containsPair(_C.scheduling, _S.ok));
        expect(
          iosDiagnostics(_ios(os: '16.4'))[_C.buttons]!.message,
          contains('none are shown'),
        );
      },
    );

    test('widget extension problems', () {
      expect(
        iosDiagnostics(_ios(widgets: const []))[_C.widgetExtension],
        isA<LiveUpdateDiagnosticItem>()
            .having((i) => i.status, 'status', _S.problem)
            .having((i) => i.hint, 'hint', contains('create ios')),
      );
      final tooNew = iosDiagnostics(
        _ios(
          os: '16.4',
          widgets: const [
            {'marked': true, 'minimum': '17.2', 'runs': false},
          ],
        ),
      )[_C.widgetExtension]!;
      expect(tooNew.status, _S.problem);
      expect(tooNew.message, contains('17.2'));
      // Made before the marker existed.
      expect(
        iosDiagnostics(
          _ios(
            widgets: const [
              {'marked': false, 'minimum': '16.2', 'runs': true},
            ],
          ),
        )[_C.widgetExtension]!.status,
        _S.warning,
      );
      expect(
        iosDiagnostics(
          _ios(
            widgets: const [
              {'marked': false, 'minimum': '28.0', 'runs': false},
            ],
          ),
        )[_C.widgetExtension]!.status,
        _S.problem,
      );
    });

    test('settings and Info.plist', () {
      final d = iosDiagnostics(
        _ios(
          supports: false,
          enabled: false,
          reachable: false,
          tapScheme: false,
        ),
      );
      expect(_statuses(d), containsPair(_C.supportsLiveActivities, _S.problem));
      expect(_statuses(d), containsPair(_C.liveActivitiesEnabled, _S.problem));
      expect(d[_C.liveActivitiesEnabled]!.hint, contains('openSettings'));
      expect(_statuses(d), containsPair(_C.appGroup, _S.problem));
      expect(_statuses(d), containsPair(_C.tapUrlScheme, _S.warning));
      expect(d.problems, hasLength(3));
      expect(
        iosDiagnostics(_ios(group: null))[_C.appGroup]!.status,
        _S.notApplicable,
      );
    });

    test('missing facts do not throw', () {
      final d = iosDiagnostics(const {});
      expect(d.osVersion, '0');
      expect(d[_C.osVersion]!.status, _S.problem);
    });
  });

  group('Android', () {
    test('a complete setup on Android 16', () {
      final d = androidDiagnostics(_android(), channelId: 'live_updates');
      expect(d.platform, TargetPlatform.android);
      expect(d.osVersion, '16');
      expect(_statuses(d).keys, [
        _C.osVersion,
        _C.notifications,
        _C.notificationChannel,
        _C.promotedNotifications,
        _C.exactAlarms,
        _C.defaultIcon,
      ]);
      expect(_statuses(d).values.toSet(), {_S.ok});
    });

    test('not attached', () {
      final d = androidDiagnostics(
        _android(attached: false),
        channelId: 'live_updates',
      );
      expect(d.items.single.check, _C.pluginAttached);
      expect(d.items.single.status, _S.problem);
    });

    test('older versions show an ongoing notification', () {
      final d = androidDiagnostics(
        _android(sdk: 34, release: '14', canPostPromoted: false),
        channelId: 'live_updates',
      );
      expect(d[_C.osVersion]!.status, _S.warning);
      expect(d[_C.osVersion]!.message, contains('ongoing'));
      expect(d[_C.promotedNotifications]!.status, _S.notApplicable);
      expect(d.hasNoProblems, isTrue);
    });

    test('notifications and permission', () {
      final denied = androidDiagnostics(
        _android(enabled: false, granted: false),
        channelId: 'live_updates',
      )[_C.notifications]!;
      expect(denied.status, _S.problem);
      expect(denied.hint, contains('requestPermission'));
      final off = androidDiagnostics(
        _android(enabled: false, granted: null),
        channelId: 'live_updates',
      )[_C.notifications]!;
      expect(off.status, _S.problem);
      expect(off.hint, contains('openSettings'));
    });

    test('channel states', () {
      _S status(Map<String, Object?>? channel) => androidDiagnostics(
        _android(channel: channel),
        channelId: 'live_updates',
      )[_C.notificationChannel]!.status;
      expect(status(const {'exists': false}), _S.ok);
      expect(
        status(const {'exists': true, 'importance': 0, 'groupBlocked': false}),
        _S.problem,
      );
      expect(
        status(const {'exists': true, 'importance': 1, 'groupBlocked': false}),
        _S.warning,
      );
      expect(
        status(const {'exists': true, 'importance': 4, 'groupBlocked': true}),
        _S.problem,
      );
      expect(status(null), _S.notApplicable);
    });

    test('promotion, exact alarms and the default icon', () {
      Map<_C, _S> of(Map<String, Object?> facts) =>
          _statuses(androidDiagnostics(facts, channelId: 'live_updates'));
      expect(
        of(_android(promotedDeclared: false)),
        containsPair(_C.promotedNotifications, _S.problem),
      );
      expect(
        of(_android(canPostPromoted: false)),
        containsPair(_C.promotedNotifications, _S.warning),
      );
      expect(
        of(_android(exactDeclared: false, canExact: false)),
        containsPair(_C.exactAlarms, _S.notApplicable),
      );
      expect(
        of(_android(canExact: false)),
        containsPair(_C.exactAlarms, _S.warning),
      );
      expect(
        of(_android(sdk: 30, exactDeclared: false, canExact: true)),
        containsPair(_C.exactAlarms, _S.ok),
      );
      expect(
        of(_android(defaultIcon: 'invalid')),
        containsPair(_C.defaultIcon, _S.warning),
      );
      expect(
        of(_android(defaultIcon: 'unset')),
        containsPair(_C.defaultIcon, _S.ok),
      );
    });
  });

  test('the report lists every check with its status and hint', () {
    final d = androidDiagnostics(
      _android(enabled: false, granted: false),
      channelId: 'live_updates',
    );
    final report = d.toString();
    expect(report.split('\n').first, contains('Android 16): 1 problem(s)'));
    expect(report, contains('problem       notifications: '));
    expect(report, contains('→ Call LiveUpdates.requestPermission()'));
    expect(report.split('\n'), hasLength(d.items.length + 1));
    expect(
      d,
      androidDiagnostics(
        _android(enabled: false, granted: false),
        channelId: 'live_updates',
      ),
    );
  });
}
