import 'dart:async';

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
      );
    LiveUpdates.isSupported().then((s) => _add('supported: $s'));
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
    ios: IosLiveUpdateOptions(
      layout: _layout,
      // The compact Dynamic Island shows the countdown instead of the progress.
      compactTrailing: IosIslandContent.timer,
      // Accent for progress, buttons and the timer.
      color: const Color(0xFF8C9EFF),
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
      mode: _mode,
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
    } on Object catch (e) {
      _add('$label: $e');
    }
  }

  Future<void> _start() => _run('start', () async {
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
