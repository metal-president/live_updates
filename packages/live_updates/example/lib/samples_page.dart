import 'package:live_updates/live_updates.dart';
import 'package:material_ui/material_ui.dart';

/// A sample live update to check on a simulator or emulator.
class Sample {
  const Sample(this.name, this.description, this.content);

  final String name;
  final String description;

  /// Built on every Show, so text edited here appears after a Hot Reload.
  final LiveUpdateContent Function() content;

  /// Each sample has a key of its own: Show again updates it in place.
  String get key => 'sample-$name';
}

const _icon = LiveUpdateIcon.symbol('shippingbox.fill');
const _androidIcon = AndroidLiveUpdateOptions(
  smallIcon: LiveUpdateIcon.native('ic_stat_parcel'),
);

DateTime _inMinutes(int minutes) =>
    DateTime.now().add(Duration(minutes: minutes));

/// One sample per built-in layout, a custom layout, content hidden on the
/// Lock Screen and content that switches to its ended version. Edit the
/// texts, Hot Reload and tap Show to check them on the device.
final samples = <Sample>[
  Sample(
    'standard',
    'Title, body, progress and a countdown',
    () => LiveUpdateContent(
      title: 'Order #1234',
      body: 'On the way',
      progress: .6,
      icon: _icon,
      timer: LiveUpdateTimer.countdown(_inMinutes(15)),
      android: _androidIcon,
    ),
  ),
  Sample(
    'timer',
    'A large countdown (iOS timer layout)',
    () => LiveUpdateContent(
      title: 'Order #1234',
      body: 'Arriving soon',
      icon: _icon,
      timer: LiveUpdateTimer.countdown(_inMinutes(15)),
      ios: const IosLiveUpdateOptions(
        layout: IosLiveUpdateLayout.timer,
        compactTrailing: IosIslandContent.timer,
      ),
      android: _androidIcon,
    ),
  ),
  Sample(
    'metrics',
    'Three values (iOS metrics layout, Android 17 MetricStyle)',
    () => LiveUpdateContent(
      title: 'Order #1234',
      body: 'On the way',
      icon: _icon,
      metrics: [
        LiveUpdateMetric.timer('Arrives in', _inMinutes(15)),
        const LiveUpdateMetric.decimal('Distance', 2.4, unit: 'km'),
        const LiveUpdateMetric.integer('Stops', 2),
      ],
      ios: const IosLiveUpdateOptions(layout: IosLiveUpdateLayout.metrics),
      android: _androidIcon,
    ),
  ),
  Sample(
    'stepper',
    'Stages (iOS stepper layout, Android 16 progress segments)',
    () => const LiveUpdateContent(
      title: 'Order #1234',
      body: 'On the way',
      icon: _icon,
      steps: LiveUpdateSteps([
        'Ordered',
        'Preparing',
        'On the way',
        'Delivered',
      ], current: 2),
      ios: IosLiveUpdateOptions(layout: IosLiveUpdateLayout.stepper),
      android: _androidIcon,
    ),
  ),
  Sample(
    'journey',
    'From and to (iOS journey layout)',
    () => const LiveUpdateContent(
      title: 'Order #1234',
      body: 'On the way',
      progress: .6,
      icon: _icon,
      journey: LiveUpdateJourney(
        from: 'Shop',
        to: 'Home',
        fromDetail: '18:10',
        toDetail: '18:30',
      ),
      ios: IosLiveUpdateOptions(layout: IosLiveUpdateLayout.journey),
      android: _androidIcon,
    ),
  ),
  Sample(
    'custom',
    'The delivery layout (SwiftUI and res/layout XML)',
    () => LiveUpdateContent(
      title: 'Order #1234',
      progress: .6,
      timer: LiveUpdateTimer.countdown(_inMinutes(15)),
      image: const LiveUpdateImage.asset(
        'assets/parcel.png',
        maxDimension: 128,
      ),
      extra: const {
        'status': 'The courier is nearby',
        'distance': '1.6 km',
        'stops': '1',
        'arrival': '18:30',
      },
      extraImages: const {
        'courier': LiveUpdateImage.asset(
          'assets/courier.png',
          maxDimension: 96,
        ),
      },
      ios: const IosLiveUpdateOptions(
        layout: IosLiveUpdateLayout.custom('delivery'),
      ),
      android: const AndroidLiveUpdateOptions(
        smallIcon: LiveUpdateIcon.native('ic_stat_parcel'),
        mode: AndroidLiveUpdateMode.ongoing,
        customLayout: AndroidCustomLayout(
          'live_update_delivery',
          expanded: 'live_update_delivery_expanded',
        ),
      ),
    ),
  ),
  Sample(
    'hidden',
    'publicContent, shown on a locked device that hides sensitive content',
    () => LiveUpdateContent(
      title: 'Order #1234: 2 items',
      body: 'Leave at the side door',
      progress: .6,
      icon: _icon,
      timer: LiveUpdateTimer.countdown(_inMinutes(15)),
      publicContent: const LiveUpdatePublicContent(
        title: 'Delivery',
        body: 'Unlock for details',
      ),
      android: _androidIcon,
    ),
  ),
  Sample(
    'ended',
    'Switches to endedContent 20 seconds after Show (Android: on time '
        'with exact alarms)',
    () => LiveUpdateContent(
      title: 'Order #1234',
      body: 'Arriving now',
      progress: .9,
      icon: _icon,
      endAt: DateTime.now().add(const Duration(seconds: 20)),
      endedContent: const LiveUpdateEndedContent(
        title: 'Order #1234',
        body: 'Delivered',
        icon: LiveUpdateIcon.symbol('checkmark.circle.fill'),
      ),
      android: _androidIcon,
    ),
  ),
];

/// Shows, updates and ends the [samples] on the device, with the result of
/// [LiveUpdateContent.check] for each, and [LiveUpdates.diagnose] on top.
class SamplesPage extends StatefulWidget {
  const SamplesPage({super.key});

  @override
  State<SamplesPage> createState() => _SamplesPageState();
}

class _SamplesPageState extends State<SamplesPage> {
  String _diagnostics = 'Tap Diagnose to check the setup.';
  String _status = '';

  Future<void> _diagnose() async {
    final d = await LiveUpdates.diagnose();
    debugPrint('$d');
    setState(() => _diagnostics = '$d');
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    try {
      await action();
      setState(() => _status = '$label: ok');
    } on LiveUpdateException catch (e) {
      setState(() => _status = '$label: ${e.reason.name}: ${e.message}');
    } on Object catch (e) {
      setState(() => _status = '$label: $e');
    }
  }

  Future<void> _show(Sample s) => _run('show ${s.name}', () async {
    if (!await LiveUpdates.requestPermission()) {
      throw StateError('not allowed or not supported on this device');
    }
    await LiveUpdates.startOrUpdate(s.key, s.content());
  });

  Future<void> _end(Sample s) => _run('end ${s.name}', () async {
    await (await LiveUpdates.find(s.key))?.end(dismissAfter: Duration.zero);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Samples')),
    body: ListView(
      children: [
        ListTile(
          title: const Text('Setup'),
          subtitle: SelectableText(
            _diagnostics,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          trailing: OutlinedButton(
            onPressed: _diagnose,
            child: const Text('Diagnose'),
          ),
        ),
        if (_status.isNotEmpty) ListTile(dense: true, title: Text(_status)),
        const Divider(),
        for (final s in samples) _SampleTile(s, _show, _end),
        ListTile(
          title: const Text('End all'),
          trailing: OutlinedButton(
            onPressed: () => _run('end all', LiveUpdates.endAll),
            child: const Text('End all'),
          ),
        ),
      ],
    ),
  );
}

class _SampleTile extends StatelessWidget {
  const _SampleTile(this.sample, this.show, this.end);

  final Sample sample;
  final Future<void> Function(Sample) show;
  final Future<void> Function(Sample) end;

  @override
  Widget build(BuildContext context) {
    // Checked on every build, so it follows edits after a Hot Reload.
    final issues = sample.content().check();
    return ListTile(
      title: Text(sample.name),
      subtitle: Text(
        [sample.description, for (final i in issues) '• $i'].join('\n'),
      ),
      isThreeLine: issues.isNotEmpty,
      trailing: Wrap(
        spacing: 4,
        children: [
          FilledButton(
            onPressed: () => show(sample),
            child: const Text('Show'),
          ),
          OutlinedButton(
            onPressed: () => end(sample),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}
