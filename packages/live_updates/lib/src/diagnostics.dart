import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:meta/meta.dart';

/// Result of one check of [LiveUpdateDiagnostics].
enum LiveUpdateDiagnosticStatus {
  /// Set up as needed.
  ok,

  /// Live updates appear, but something works differently than you may
  /// expect, such as no buttons before iOS 17.0.
  warning,

  /// Live updates, or a part of them, do not appear until this is fixed.
  problem,

  /// The check does not apply here, such as the App Group of an app that
  /// does not use one.
  notApplicable,
}

/// What a [LiveUpdateDiagnosticItem] checks. The names are stable; handle
/// unknown values with a default branch, as checks may be added in minor
/// releases.
enum LiveUpdateDiagnosticCheck {
  /// Reported only where live updates do nothing (platforms other than iOS
  /// and Android).
  platform,

  /// The OS version and what it shows: iOS 16.2 for Live Activities;
  /// Android 16 for `ProgressStyle` and, from Android 16 QPR1, promotion to
  /// Live Updates (older versions show an ongoing notification).
  osVersion,

  /// iOS: the widget extension made by `create ios` is in the app and
  /// supports the running iOS.
  widgetExtension,

  /// iOS: `NSSupportsLiveActivities` is YES in the Runner `Info.plist`.
  supportsLiveActivities,

  /// iOS: the user allows Live Activities for the app.
  liveActivitiesEnabled,

  /// iOS: the App Group for images and asset icons is reachable.
  appGroup,

  /// iOS: the URL scheme that brings taps and open-app buttons to the app is
  /// registered.
  tapUrlScheme,

  /// iOS: buttons, which need iOS 17.0.
  buttons,

  /// iOS: push-to-start tokens, which need iOS 17.2.
  pushToStart,

  /// iOS: [LiveUpdates.schedule], which needs iOS 26.
  scheduling,

  /// Android: the plugin is attached to a Flutter engine.
  pluginAttached,

  /// Android: notifications are enabled for the app (and the
  /// `POST_NOTIFICATIONS` permission is granted on Android 13+).
  notifications,

  /// Android 8.0+: the notification channel is not turned off.
  notificationChannel,

  /// Android 16+: `POST_PROMOTED_NOTIFICATIONS` is declared and the system
  /// lets the app post promoted notifications (Live Updates).
  promotedNotifications,

  /// Android: exact alarms for [LiveUpdates.schedule] and
  /// [LiveUpdateContent.endAt].
  exactAlarms,

  /// Android: the `com.ttechapp.live_updates.default_icon` meta-data.
  defaultIcon,
}

/// One check of [LiveUpdates.diagnose].
@immutable
final class LiveUpdateDiagnosticItem {
  /// Creates an item.
  const LiveUpdateDiagnosticItem(
    this.check,
    this.status,
    this.message, {
    this.hint,
  });

  /// What was checked.
  final LiveUpdateDiagnosticCheck check;

  /// The result.
  final LiveUpdateDiagnosticStatus status;

  /// What was found, in English.
  final String message;

  /// What to do about it, such as a call to make, or `null`.
  final String? hint;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateDiagnosticItem &&
      other.check == check &&
      other.status == status &&
      other.message == message &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(check, status, message, hint);

  @override
  String toString() =>
      '${status.name.padRight(13)} ${check.name}: $message'
      '${hint == null ? '' : ' → $hint'}';
}

/// Why live updates may not appear on this device, from
/// [LiveUpdates.diagnose].
@immutable
final class LiveUpdateDiagnostics {
  /// Creates diagnostics.
  const LiveUpdateDiagnostics({
    required this.platform,
    required this.osVersion,
    required this.items,
  });

  /// Diagnostics of a platform where live updates do nothing.
  const LiveUpdateDiagnostics.unsupported()
    : platform = null,
      osVersion = null,
      items = const [
        LiveUpdateDiagnosticItem(
          LiveUpdateDiagnosticCheck.platform,
          LiveUpdateDiagnosticStatus.problem,
          'Live updates are shown on iOS and Android only; here every call '
          'does nothing.',
        ),
      ];

  /// [TargetPlatform.iOS] or [TargetPlatform.android], or `null` on a
  /// platform where live updates do nothing.
  final TargetPlatform? platform;

  /// The OS version, such as `17.2.1` on iOS or `16` on Android, or `null`
  /// when unknown.
  final String? osVersion;

  /// Every check, in a fixed order.
  final List<LiveUpdateDiagnosticItem> items;

  /// The item for [check], or `null` when it was not checked here.
  LiveUpdateDiagnosticItem? operator [](LiveUpdateDiagnosticCheck check) {
    for (final i in items) {
      if (i.check == check) return i;
    }
    return null;
  }

  /// Items with [LiveUpdateDiagnosticStatus.problem].
  List<LiveUpdateDiagnosticItem> get problems => [
    for (final i in items)
      if (i.status == LiveUpdateDiagnosticStatus.problem) i,
  ];

  /// Items with [LiveUpdateDiagnosticStatus.warning].
  List<LiveUpdateDiagnosticItem> get warnings => [
    for (final i in items)
      if (i.status == LiveUpdateDiagnosticStatus.warning) i,
  ];

  /// Whether no check found a problem.
  bool get hasNoProblems => problems.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateDiagnostics &&
      other.platform == platform &&
      other.osVersion == osVersion &&
      _listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(platform, osVersion, Object.hashAll(items));

  /// A readable report, one line per check, for logs.
  @override
  String toString() {
    final where = switch (platform) {
      TargetPlatform.iOS => 'iOS $osVersion',
      TargetPlatform.android => 'Android $osVersion',
      _ => 'unsupported platform',
    };
    final summary = problems.isNotEmpty
        ? '${problems.length} problem(s)'
        : warnings.isNotEmpty
        ? '${warnings.length} warning(s)'
        : 'no problems';
    return [
      'live_updates diagnostics ($where): $summary',
      for (final i in items) '  $i',
    ].join('\n');
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _ok = LiveUpdateDiagnosticStatus.ok;
const _warning = LiveUpdateDiagnosticStatus.warning;
const _problem = LiveUpdateDiagnosticStatus.problem;
const _na = LiveUpdateDiagnosticStatus.notApplicable;

/// `[major, minor, patch]` of [version], missing parts as 0.
List<int> _version(String version) {
  final parts = [for (final p in version.split('.')) int.tryParse(p) ?? 0];
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

bool _atLeast(List<int> v, int major, [int minor = 0]) =>
    v[0] > major || (v[0] == major && v[1] >= minor);

/// Diagnostics from the facts the iOS bridge reports
/// (`LiveUpdatesBridge.diagnosticsJson`).
LiveUpdateDiagnostics iosDiagnostics(Map<String, Object?> facts) {
  final os = switch (facts['os']) {
    final String s => s,
    _ => '0',
  };
  final v = _version(os);
  final live = _atLeast(v, 16, 2);
  final items = <LiveUpdateDiagnosticItem>[];
  void add(
    LiveUpdateDiagnosticCheck check,
    LiveUpdateDiagnosticStatus status,
    String message, [
    String? hint,
  ]) => items.add(LiveUpdateDiagnosticItem(check, status, message, hint: hint));

  live
      ? add(
          LiveUpdateDiagnosticCheck.osVersion,
          _ok,
          'iOS $os supports Live Activities (16.2 or later).',
        )
      : add(
          LiveUpdateDiagnosticCheck.osVersion,
          _problem,
          'iOS $os: Live Activities need iOS 16.2; every call does nothing.',
        );

  final widgets = [
    for (final w in switch (facts['widgets']) {
      final List<Object?> l => l,
      _ => const <Object?>[],
    })
      if (w is Map) w,
  ];
  final marked = [
    for (final w in widgets)
      if (w['marked'] == true) w,
  ];
  if (!live) {
    add(
      LiveUpdateDiagnosticCheck.widgetExtension,
      _na,
      'Not used before iOS 16.2.',
    );
  } else if (widgets.isEmpty) {
    add(
      LiveUpdateDiagnosticCheck.widgetExtension,
      _problem,
      'The app has no widget extension, which draws Live Activities.',
      'Run `dart run live_updates:create ios`.',
    );
  } else if (marked.isNotEmpty) {
    final old = [
      for (final w in marked)
        if (w['runs'] != true) w['minimum'],
    ];
    old.isEmpty
        ? add(
            LiveUpdateDiagnosticCheck.widgetExtension,
            _ok,
            'The widget extension made by create ios supports this iOS.',
          )
        : add(
            LiveUpdateDiagnosticCheck.widgetExtension,
            _problem,
            'The widget extension needs iOS ${old.join(', ')}, newer than '
                '$os, so no Live Activity appears.',
            'Lower the deployment target of the widget extension to 16.2.',
          );
  } else {
    widgets.any((w) => w['runs'] == true)
        ? add(
            LiveUpdateDiagnosticCheck.widgetExtension,
            _warning,
            'Found a widget extension without the LiveUpdatesWidget marker '
                'that create ios adds since live_updates 0.4.0.',
            'Run `dart run live_updates:create ios` again.',
          )
        : add(
            LiveUpdateDiagnosticCheck.widgetExtension,
            _problem,
            'No widget extension supports iOS $os, so no Live Activity '
                'appears.',
            'Lower the deployment target of the widget extension to 16.2.',
          );
  }

  facts['supportsLiveActivities'] == true
      ? add(
          LiveUpdateDiagnosticCheck.supportsLiveActivities,
          _ok,
          'NSSupportsLiveActivities is YES in the Runner Info.plist.',
        )
      : add(
          LiveUpdateDiagnosticCheck.supportsLiveActivities,
          _problem,
          'NSSupportsLiveActivities is not YES in the Runner Info.plist, so '
              'the app cannot start Live Activities.',
          'Run `dart run live_updates:create ios`, which sets it.',
        );

  switch (facts['activitiesEnabled']) {
    case true:
      add(
        LiveUpdateDiagnosticCheck.liveActivitiesEnabled,
        _ok,
        'Live Activities are allowed for the app.',
      );
    case false:
      add(
        LiveUpdateDiagnosticCheck.liveActivitiesEnabled,
        _problem,
        'Live Activities are turned off for the app in Settings.',
        'Offer LiveUpdates.openSettings().',
      );
    default:
      add(
        LiveUpdateDiagnosticCheck.liveActivitiesEnabled,
        _na,
        'Not available before iOS 16.2.',
      );
  }

  if (facts['appGroup'] is! String) {
    add(
      LiveUpdateDiagnosticCheck.appGroup,
      _na,
      'No App Group is set up (LiveUpdatesAppGroup in the Runner Info.plist); '
      'images and asset icons need one.',
    );
  } else if (facts['appGroupReachable'] == true) {
    add(
      LiveUpdateDiagnosticCheck.appGroup,
      _ok,
      'The App Group in LiveUpdatesAppGroup is reachable.',
    );
  } else {
    add(
      LiveUpdateDiagnosticCheck.appGroup,
      _problem,
      'The App Group in LiveUpdatesAppGroup is not reachable, so images and '
          'asset icons are not shown.',
      'Enable the App Group capability with that group for Runner and the '
          'widget extension.',
    );
  }

  facts['tapScheme'] == true
      ? add(
          LiveUpdateDiagnosticCheck.tapUrlScheme,
          _ok,
          'The tap URL scheme is registered.',
        )
      : add(
          LiveUpdateDiagnosticCheck.tapUrlScheme,
          _warning,
          'The URL scheme liveupdates-<bundle id> is not registered in the '
              'Runner Info.plist; onTap routes and buttons that open the app '
              'rely on it.',
          'Run `dart run live_updates:create ios`, which registers it.',
        );

  for (final (check, major, minor, what) in [
    (LiveUpdateDiagnosticCheck.buttons, 17, 0, 'Buttons'),
    (LiveUpdateDiagnosticCheck.pushToStart, 17, 2, 'Push-to-start'),
    (LiveUpdateDiagnosticCheck.scheduling, 26, 0, 'Scheduling'),
  ]) {
    final needs = 'iOS $major${minor == 0 ? '' : '.$minor'}';
    if (!live) {
      add(check, _na, '$what needs $needs.');
    } else if (_atLeast(v, major, minor)) {
      add(check, _ok, '$what available ($needs or later).');
    } else {
      add(check, _warning, switch (check) {
        LiveUpdateDiagnosticCheck.buttons =>
          'Buttons need $needs; none are shown on iOS $os.',
        LiveUpdateDiagnosticCheck.pushToStart =>
          'Push-to-start needs $needs; no push-to-start token on iOS $os.',
        _ => 'Scheduling needs $needs; LiveUpdates.schedule throws on iOS $os.',
      });
    }
  }
  return LiveUpdateDiagnostics(
    platform: TargetPlatform.iOS,
    osVersion: os,
    items: List.unmodifiable(items),
  );
}

/// `NotificationManager.IMPORTANCE_NONE` and `IMPORTANCE_MIN`.
const _importanceNone = 0;
const _importanceMin = 1;

/// Diagnostics from the facts the Android bridge reports
/// (`LiveUpdatesBridge.diagnosticsJson`) for the channel [channelId].
LiveUpdateDiagnostics androidDiagnostics(
  Map<String, Object?> facts, {
  required String channelId,
}) {
  final sdk = switch (facts['sdk']) {
    final num n => n.toInt(),
    _ => 0,
  };
  final release = switch (facts['release']) {
    final String s => s,
    _ => '$sdk',
  };
  final items = <LiveUpdateDiagnosticItem>[];
  void add(
    LiveUpdateDiagnosticCheck check,
    LiveUpdateDiagnosticStatus status,
    String message, [
    String? hint,
  ]) => items.add(LiveUpdateDiagnosticItem(check, status, message, hint: hint));

  if (facts['attached'] != true) {
    add(
      LiveUpdateDiagnosticCheck.pluginAttached,
      _problem,
      'live_updates is not attached to a Flutter engine yet.',
      'Call diagnose() after runApp, or after '
          'WidgetsFlutterBinding.ensureInitialized().',
    );
    return LiveUpdateDiagnostics(
      platform: TargetPlatform.android,
      osVersion: release,
      items: List.unmodifiable(items),
    );
  }

  sdk >= 36
      ? add(
          LiveUpdateDiagnosticCheck.osVersion,
          _ok,
          'Android $release (API $sdk): live updates use the Android 16 styles '
          'and can be promoted to Live Updates when the system allows it '
          '(Android 16 QPR1 and later).',
        )
      : add(
          LiveUpdateDiagnosticCheck.osVersion,
          _warning,
          'Android $release (API $sdk): live updates are regular ongoing '
          'notifications; Live Updates need Android 16 QPR1 or later.',
        );

  if (facts['notificationsEnabled'] == true) {
    add(
      LiveUpdateDiagnosticCheck.notifications,
      _ok,
      'Notifications are enabled for the app.',
    );
  } else if (facts['postNotificationsGranted'] == false) {
    add(
      LiveUpdateDiagnosticCheck.notifications,
      _problem,
      'The POST_NOTIFICATIONS permission is not granted, so nothing is '
          'shown.',
      'Call LiveUpdates.requestPermission(), or offer '
          'LiveUpdates.openSettings() if the user denied it.',
    );
  } else {
    add(
      LiveUpdateDiagnosticCheck.notifications,
      _problem,
      'Notifications are turned off for the app, so nothing is shown.',
      'Offer LiveUpdates.openSettings().',
    );
  }

  switch (facts['channel']) {
    case {'exists': false}:
      add(
        LiveUpdateDiagnosticCheck.notificationChannel,
        _ok,
        'The channel "$channelId" is created with the first live update.',
      );
    case {'groupBlocked': true}:
      add(
        LiveUpdateDiagnosticCheck.notificationChannel,
        _problem,
        'The group of the channel "$channelId" is turned off, so nothing is '
            'shown on it.',
        'Offer LiveUpdates.openSettings().',
      );
    case {'importance': final num i} when i.toInt() == _importanceNone:
      add(
        LiveUpdateDiagnosticCheck.notificationChannel,
        _problem,
        'The channel "$channelId" is turned off, so nothing is shown on it.',
        'Offer LiveUpdates.openSettings().',
      );
    case {'importance': final num i} when i.toInt() == _importanceMin:
      add(
        LiveUpdateDiagnosticCheck.notificationChannel,
        _warning,
        'The channel "$channelId" has the minimum importance; Android does '
            'not promote its notifications to Live Updates.',
        'Use a channel with a higher importance.',
      );
    case {'exists': true}:
      add(
        LiveUpdateDiagnosticCheck.notificationChannel,
        _ok,
        'The channel "$channelId" is enabled.',
      );
    default:
      add(
        LiveUpdateDiagnosticCheck.notificationChannel,
        _na,
        'Notification channels exist from Android 8.0.',
      );
  }

  if (sdk < 36) {
    add(
      LiveUpdateDiagnosticCheck.promotedNotifications,
      _na,
      'Promoted notifications (Live Updates) need Android 16 QPR1 or later.',
    );
  } else if (facts['promotedDeclared'] != true) {
    add(
      LiveUpdateDiagnosticCheck.promotedNotifications,
      _problem,
      'POST_PROMOTED_NOTIFICATIONS is not in the merged manifest, so '
          'nothing is promoted to a Live Update.',
      'Do not remove the permission that live_updates declares.',
    );
  } else if (facts['canPostPromoted'] == true) {
    add(
      LiveUpdateDiagnosticCheck.promotedNotifications,
      _ok,
      'The app may post promoted notifications (Live Updates).',
    );
  } else {
    add(
      LiveUpdateDiagnosticCheck.promotedNotifications,
      _warning,
      'The app may not post promoted notifications: the user turned Live '
      'Updates off for the app, or this Android build has no promoted '
      'notification support (it needs Android 16 QPR1 or later). Live '
      'updates appear as ongoing notifications.',
    );
  }

  if (sdk < 31) {
    add(
      LiveUpdateDiagnosticCheck.exactAlarms,
      _ok,
      'Every app may set exact alarms before Android 12.',
    );
  } else if (facts['exactAlarmDeclared'] != true) {
    add(
      LiveUpdateDiagnosticCheck.exactAlarms,
      _na,
      'SCHEDULE_EXACT_ALARM is not declared; scheduled live updates appear '
      'within AndroidScheduleOptions.window and endedContent within 10 '
      'minutes.',
    );
  } else if (facts['canScheduleExactly'] == true) {
    add(
      LiveUpdateDiagnosticCheck.exactAlarms,
      _ok,
      'The app may set exact alarms.',
    );
  } else {
    add(
      LiveUpdateDiagnosticCheck.exactAlarms,
      _warning,
      'The user has not allowed exact alarms; scheduled live updates appear '
          'within AndroidScheduleOptions.window and endedContent within 10 '
          'minutes.',
      'Offer LiveUpdates.openExactAlarmSettings().',
    );
  }

  switch (facts['defaultIcon']) {
    case 'valid':
      add(
        LiveUpdateDiagnosticCheck.defaultIcon,
        _ok,
        'The default icon meta-data names a drawable or mipmap.',
      );
    case 'invalid':
      add(
        LiveUpdateDiagnosticCheck.defaultIcon,
        _warning,
        'The com.ttechapp.live_updates.default_icon meta-data is not a '
            'drawable, so the app icon is used for content without an icon.',
        'Set it to android:resource="@drawable/...".',
      );
    default:
      add(
        LiveUpdateDiagnosticCheck.defaultIcon,
        _ok,
        'No default icon meta-data: content without an icon shows the app '
        'icon, of which Android draws only the shape.',
      );
  }
  return LiveUpdateDiagnostics(
    platform: TargetPlatform.android,
    osVersion: release,
    items: List.unmodifiable(items),
  );
}
