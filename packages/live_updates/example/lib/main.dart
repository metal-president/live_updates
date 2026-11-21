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
    image: const LiveUpdateImage.asset('assets/parcel.png', maxDimension: 128),
    actions: const [
      LiveUpdateAction(
        id: 'cancel',
        title: 'Cancel',
        iosSystemImage: 'xmark',
        // Destructive: ask for an unlock on the Lock Screen first.
        requiresUnlock: true,
      ),
      LiveUpdateAction(
        id: 'details',
        title: 'Details',
        opensApp: true,
        iosSystemImage: 'list.bullet',
      ),
    ],
    android: AndroidLiveUpdateOptions(
      shortCriticalText: 'ETA',
      // Android 17+: shown instead of the progress bar.
      metrics: [
        AndroidMetric.timer('Arrives in', _eta),
        AndroidMetric.decimal('Distance', (1 - _progress) * 4, unit: 'km'),
      ],
      bodySemanticStyle: _progress >= 1
          ? LiveUpdateSemanticStyle.safe
          : LiveUpdateSemanticStyle.info,
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
