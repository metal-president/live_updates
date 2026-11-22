import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/background.dart';
import 'package:live_updates/src/platform/live_updates_platform.dart';

class QueuePlatform extends NoopLiveUpdatesPlatform {
  QueuePlatform(this.batches, {this.handle = 1});

  final List<List<(String, String)>> batches;
  final int? handle;
  var takes = 0;
  var done = 0;

  @override
  Future<int?> backgroundActionHandler() async => handle;

  @override
  Future<List<(String, String)>> takeQueuedActions() async {
    takes++;
    return batches.isEmpty ? [] : batches.removeAt(0);
  }

  @override
  Future<void> backgroundActionsDone() async => done++;
}

final _handled = <String>[];

Future<void> _handler(LiveUpdateActionEvent e) async {
  if (e.actionId == 'boom') throw StateError('handler failed');
  _handled.add('${e.updateId}:${e.actionId}');
}

void main() {
  setUp(_handled.clear);

  test('drains until the queue is empty, then reports done', () async {
    final p = QueuePlatform([
      [('a', 'x')],
      [('b', 'y'), ('c', 'z')], // arrived while the first ran
    ]);
    await runBackgroundActions(p, (_) => _handler);
    expect(_handled, ['a:x', 'b:y', 'c:z']);
    expect(p.takes, 3);
    expect(p.done, 1);
  });

  test('a failing press does not stop the others', () async {
    final p = QueuePlatform([
      [('a', 'boom'), ('b', 'y')],
    ]);
    await runBackgroundActions(p, (_) => _handler);
    expect(_handled, ['b:y']);
    expect(p.done, 1);
  });

  test('without a handler the presses are dropped, so no rerun', () async {
    final p = QueuePlatform([
      [('a', 'x')],
    ]);
    await runBackgroundActions(p, (_) => null);
    expect(p.batches, isEmpty); // taken out of the native queue
    expect(p.done, 1);
  });

  test('a handle of something else is not called', () async {
    final p = QueuePlatform([
      [('a', 'x')],
    ]);
    await runBackgroundActions(
      p,
      (_) =>
          (int x) => x,
    );
    expect(p.batches, isEmpty);
    expect(p.done, 1);
  });

  test('done is reported even when the platform fails', () async {
    final p = _FailingPlatform();
    await runBackgroundActions(p, (_) => _handler);
    expect(p.done, 1);
  });
}

class _FailingPlatform extends QueuePlatform {
  _FailingPlatform() : super([]);

  @override
  Future<int?> backgroundActionHandler() async => throw StateError('gone');
}
