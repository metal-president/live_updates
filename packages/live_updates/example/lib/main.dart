import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:live_updates/live_updates.dart';
import 'package:material_ui/material_ui.dart';

/// Runs in a headless engine when a button is pressed while the app is not
/// running.
@pragma('vm:entry-point')
Future<void> onBackgroundAction(LiveUpdateActionEvent event) async {
  debugPrint(
    '[live_updates] background action: ${event.actionId} on ${event.updateId}',
  );
  if (event.actionId == 'cancel') {
    final active = await LiveUpdates.active();
    await active
        .where((u) => u.id == event.updateId)
        .firstOrNull
        ?.end(dismissAfter: Duration.zero);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiveUpdates.setBackgroundActionHandler(onBackgroundAction);
  runApp(const MaterialApp(home: ExamplePage()));
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final _log = <String>[];
  final _subs = <StreamSubscription<Object?>>[];
  LiveUpdate? _current;
  double _progress = 0;
  DateTime _eta = DateTime.now();
  bool _push = false;
  IosLiveUpdateLayout _layout = IosLiveUpdateLayout.standard;
  AndroidLiveUpdateMode _mode = AndroidLiveUpdateMode.liveUpdate;
  bool _customLayout = false;

  static const _layouts = {
    'standard': IosLiveUpdateLayout.standard,
    'timer': IosLiveUpdateLayout.timer,
    'metrics': IosLiveUpdateLayout.metrics,
    'stepper': IosLiveUpdateLayout.stepper,
    'journey': IosLiveUpdateLayout.journey,
  };

  @override
  void initState() {
    super.initState();
    _subs
      ..add(LiveUpdates.onTap.listen((r) => _add('tap: $r')))
      ..add(
        LiveUpdates.onAction.listen((e) {
          _add('action: ${e.actionId} on ${e.updateId}');
          if (e.actionId == 'cancel') _endById(e.updateId);
        }),
      )
      ..add(
        LiveUpdates.pushToStartTokens.listen(
          (t) => _add('push-to-start: ${t.hex}'),
        ),
      )
      // Also reports scheduled updates when their time comes.
      ..add(LiveUpdates.onStarted.listen((u) => _add('started: ${u.id}')));
    LiveUpdates.isSupported().then((s) => _add('supported: $s'));
    LiveUpdates.canSchedule().then((s) => _add('can schedule: $s'));
    // Android 16 QPR1+: whether the user allows promoted Live Updates.
    LiveUpdates.canPostPromotedNotifications().then(
      (s) => _add('can post promoted: $s'),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _add(String line) {
    debugPrint('[live_updates] $line');
    if (mounted) setState(() => _log.insert(0, line));
  }

  LiveUpdateContent _content() => LiveUpdateContent(
    title: 'Order #1234',
    body: _progress >= 1 ? 'Delivered' : 'On the way',
    progress: _progress,
    route: '/orders/1234',
    // At the ETA the update shows "Delivered", even if the app is closed.
    endAt: _eta,
    endedContent: const LiveUpdateEndedContent(
      title: 'Order #1234',
      body: 'Delivered',
      icon: LiveUpdateIcon.symbol('checkmark.circle.fill'),
    ),
    // Counted by the system: no update needed every second.
    timer: LiveUpdateTimer.countdown(_eta),
    // Data for the metrics, stepper and journey layouts, sent only with the
    // layout that shows it so each one can be compared. Android shows the
    // same data its own way: metrics (Android 17), stages as progress
    // segments, text.
    metrics: [
      if (_layout == IosLiveUpdateLayout.metrics) ...[
        LiveUpdateMetric.timer('Arrives in', _eta),
        LiveUpdateMetric.decimal(
          'Distance',
          (1 - _progress) * 4,
          unit: 'km',
          semanticStyle: _progress >= 1
              ? LiveUpdateSemanticStyle.safe
              : LiveUpdateSemanticStyle.info,
        ),
      ],
    ],
    steps: _layout == IosLiveUpdateLayout.stepper
        ? LiveUpdateSteps(const [
            'Ordered',
            'Preparing',
            'On the way',
            'Delivered',
          ], current: (_progress * 3).round())
        : null,
    journey: _layout == IosLiveUpdateLayout.journey
        ? LiveUpdateJourney(
            from: 'Shop',
            to: 'Home',
            toDetail:
                '${_eta.hour.toString().padLeft(2, '0')}:'
                '${_eta.minute.toString().padLeft(2, '0')}',
          )
        : null,
    // Values for layouts of your own ("Custom layout"): the Android layouts
    // res/layout/live_update_delivery*.xml show them in the views
    // live_update_extra_<key>, and the iOS layout "delivery" (in
    // LiveUpdatesWidgetLiveActivity.swift) reads context.state.extra.
    extra: {
      'status': switch (_progress) {
        >= 1 => 'Left at the door',
        < .5 => 'Your order is on its way',
        _ => 'The courier is nearby',
      },
      'distance': '${((1 - _progress) * 4).toStringAsFixed(1)} km',
      'stops': '${((1 - _progress) * 3).round()}',
      'arrival':
          '${_eta.hour.toString().padLeft(2, '0')}:'
          '${_eta.minute.toString().padLeft(2, '0')}',
    },
    extraImages: {
      if (_customLayout)
        'courier': const LiveUpdateImage.asset(
          'assets/courier.png',
          maxDimension: 96,
        ),
    },
    // Shown instead (keeping the progress and the countdown) while a locked
    // device hides sensitive content, if the person chose that in Settings.
    publicContent: const LiveUpdatePublicContent(
      title: 'Delivery',
      body: 'Unlock for details',
    ),
    ios: IosLiveUpdateOptions(
      layout: _customLayout
          ? const IosLiveUpdateLayout.custom('delivery')
          : _layout,
      // The compact Dynamic Island shows the countdown instead of the progress.
      compactTrailing: IosIslandContent.timer,
      // Accent for progress, buttons and the timer: readable on the dark
      // Dynamic Island and on light and dark Lock Screen cards.
      color: const Color(0xFF3D5AFE),
      // A simple shape in the Dynamic Island instead of the photo.
      islandIcon: const LiveUpdateIcon.symbol('shippingbox.fill'),
    ),
    image: const LiveUpdateImage.asset('assets/parcel.png', maxDimension: 128),
    // Shared icon (iOS thumbnail fallback); Android and the Dynamic Island
    // get their own below.
    icon: const LiveUpdateIcon.asset('assets/parcel.png'),
    actions: const [
      LiveUpdateAction(
        id: 'cancel',
        title: 'Cancel',
        icon: LiveUpdateIcon.symbol('xmark'),
        // Destructive: ask for an unlock on the Lock Screen first.
        requiresUnlock: true,
      ),
      LiveUpdateAction(
        id: 'details',
        title: 'Details',
        opensApp: true,
        icon: LiveUpdateIcon.symbol('list.bullet'),
      ),
    ],
    android: AndroidLiveUpdateOptions(
      // Single-color status bar icon (res/drawable, kept by res/raw/keep.xml).
      smallIcon: const LiveUpdateIcon.native('ic_stat_parcel'),
      // A custom layout is never promoted to a Live Update: an ongoing
      // notification says so.
      mode: _customLayout ? AndroidLiveUpdateMode.ongoing : _mode,
      // res/layout/live_update_delivery*.xml, made from the layouts that
      // `dart run live_updates:create android` writes.
      customLayout: _customLayout
          ? const AndroidCustomLayout(
              'live_update_delivery',
              expanded: 'live_update_delivery_expanded',
            )
          : null,
      shortCriticalText: 'ETA',
      // Gone after 2 hours even if the app never ends it.
      timeoutAfter: const Duration(hours: 2),
      // Sound once more when the order is delivered.
      alert: _progress >= 1,
    ),
  );

  Future<void> _run(String label, Future<void> Function() action) async {
    try {
      await action();
      _add('$label: ok');
    } on LiveUpdateException catch (e) {
      // disabled: the user turned live updates off; tap Open settings.
      _add('$label: ${e.reason.name}: ${e.message}');
    } on Object catch (e) {
      _add('$label: $e');
    }
  }

  Future<void> _start() => _run('start', () async {
    // Android 13+ asks for the notification permission; without it, start
    // throws. On iOS this is isSupported().
    if (!await LiveUpdates.requestPermission()) {
      throw StateError('not allowed or not supported on this device');
    }
    _progress = 0;
    _eta = DateTime.now().add(const Duration(minutes: 15));
    // The order number is the key: pressing Start again updates instead of
    // creating a duplicate.
    final u = await LiveUpdates.startOrUpdate(
      'order-1234',
      _content(),
      pushUpdates: _push,
    );
    _current = u;
    _subs.add(u.pushTokens.listen((t) => _add('push token: ${t.hex}')));
    _add('started ${u.id}');
  });

  Future<void> _update() => _run('update', () async {
    final current = _current;
    if (current == null) throw StateError('start a live update first');
    _progress = (_progress + .25).clamp(0, 1);
    await current.update(_content());
  });

  Future<void> _endById(String id) => _run('cancel', () async {
    final active = await LiveUpdates.active();
    await active
        .where((u) => u.id == id)
        .firstOrNull
        ?.end(dismissAfter: Duration.zero);
    if (_current?.id == id) _current = null;
  });

  Future<void> _end() => _run('end', () async {
    final current = _current;
    if (current == null) throw StateError('start a live update first');
    await current.end(dismissAfter: Duration.zero);
    _current = null;
  });

  Future<void> _listActive() => _run('active', () async {
    final active = await LiveUpdates.active();
    _add('active: ${active.map((u) => u.id).join(', ')}');
    final scheduled = await LiveUpdates.scheduled();
    _add(
      'scheduled: ${scheduled.map((s) => '${s.key} at ${s.at}').join(', ')}',
    );
  });

  /// Shows the order in a minute, even if the app is closed by then. The
  /// same key as Start: a running update for the order is updated instead.
  Future<void> _schedule() => _run('schedule', () async {
    _progress = 0;
    _eta = DateTime.now().add(const Duration(minutes: 16));
    final at = DateTime.now().add(const Duration(minutes: 1));
    final s = await LiveUpdates.schedule('order-1234', _content(), at: at);
    _add('scheduled for ${s.at}');
    // Android: on time only with exact alarms (this example declares
    // SCHEDULE_EXACT_ALARM; the user allows it in Settings).
    if (defaultTargetPlatform == TargetPlatform.android &&
        !await LiveUpdates.canScheduleExactly()) {
      _add('not exact: shown within 10 minutes; tap Exact alarms');
    }
  });

  Future<void> _cancelSchedule() => _run('cancel schedule', () async {
    await LiveUpdates.cancelScheduled('order-1234');
  });

  /// Where the user turns live updates back on (Live Activities on iOS,
  /// notifications on Android).
  Future<void> _openSettings() => _run('settings', () async {
    _add('settings opened: ${await LiveUpdates.openSettings()}');
  });

  Future<void> _openExactAlarmSettings() => _run('exact alarms', () async {
    _add('settings opened: ${await LiveUpdates.openExactAlarmSettings()}');
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('live_updates example')),
    body: Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilledButton(onPressed: _start, child: const Text('Start')),
            FilledButton(onPressed: _update, child: const Text('Update')),
            FilledButton(onPressed: _end, child: const Text('End')),
            OutlinedButton(onPressed: _listActive, child: const Text('Active')),
            FilledButton.tonal(
              onPressed: _schedule,
              child: const Text('Schedule (1 min)'),
            ),
            OutlinedButton(
              onPressed: _cancelSchedule,
              child: const Text('Cancel schedule'),
            ),
            OutlinedButton(
              onPressed: _openSettings,
              child: const Text('Open settings'),
            ),
            if (defaultTargetPlatform == TargetPlatform.android)
              OutlinedButton(
                onPressed: _openExactAlarmSettings,
                child: const Text('Exact alarms'),
              ),
          ],
        ),
        ListTile(
          title: const Text('Layout (applies on Start / Update)'),
          trailing: DropdownButton<IosLiveUpdateLayout>(
            value: _layout,
            items: [
              for (final MapEntry(:key, :value) in _layouts.entries)
                DropdownMenuItem(value: value, child: Text(key)),
            ],
            onChanged: (v) => setState(() => _layout = v ?? _layout),
          ),
        ),
        ListTile(
          title: const Text('Android display mode'),
          trailing: DropdownButton<AndroidLiveUpdateMode>(
            value: _mode,
            items: [
              for (final m in AndroidLiveUpdateMode.values)
                DropdownMenuItem(value: m, child: Text(m.name)),
            ],
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
        ),
        SwitchListTile(
          title: const Text('Custom layout (applies on Start / Update)'),
          value: _customLayout,
          onChanged: (v) => setState(() => _customLayout = v),
        ),
        SwitchListTile(
          title: const Text('Request push token (needs Push capability)'),
          value: _push,
          onChanged: (v) => setState(() => _push = v),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              for (final l in _log)
                ListTile(dense: true, title: SelectableText(l)),
            ],
          ),
        ),
      ],
    ),
  );
}
