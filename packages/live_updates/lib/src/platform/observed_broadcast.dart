import 'dart:async';

/// Button presses from a native observer that is connected only while
/// someone listens.
///
/// Native code keeps the queue: it hands Dart only the presses of the keys
/// (update ids) that current listeners want, or all of them while an
/// unfiltered listener exists. Other presses stay queued natively and the
/// background action handler runs for them, so nothing waits in memory here.
class ObservedBroadcast<T> {
  /// Creates the stream.
  ObservedBroadcast({
    required this.keyOf,
    required this.attach,
    required this.setFilter,
    required this.detach,
    required this.requeue,
  });

  /// Key (update id) of an event.
  final String Function(T event) keyOf;

  /// Connects the native observer, which calls `add` for every event of
  /// `keys` (`null`: all).
  final void Function(void Function(T event) add, Set<String>? keys) attach;

  /// Tells native code which keys Dart takes (`null`: all).
  final void Function(Set<String>? keys) setFilter;

  /// Disconnects the native observer.
  final void Function() detach;

  /// Hands events back that reached Dart after their listener left.
  final void Function(List<T> events) requeue;

  final _listeners = <_Listener<T>>[];
  bool _attached = false;

  /// Events of [key] (all when `null`).
  Stream<T> stream([String? key]) {
    late final _Listener<T> listener;
    // Synchronous: an event added is delivered before a listener can cancel,
    // so none is dropped in between.
    final controller = StreamController<T>.broadcast(sync: true);
    listener = _Listener(controller, key);
    controller
      ..onListen = (() => _addListener(listener))
      ..onCancel = (() => _removeListener(listener));
    return controller.stream;
  }

  Set<String>? get _keys => _listeners.any((l) => l.key == null)
      ? null
      : {for (final l in _listeners) l.key!};

  void _addListener(_Listener<T> listener) {
    _listeners.add(listener);
    if (!_attached) {
      _attached = true;
      attach(_deliver, _keys);
    } else {
      setFilter(_keys);
    }
  }

  void _removeListener(_Listener<T> listener) {
    _listeners.remove(listener);
    if (!_attached) return;
    if (_listeners.isEmpty) {
      _attached = false;
      detach();
    } else {
      setFilter(_keys);
    }
  }

  void _deliver(T event) {
    final key = keyOf(event);
    final targets = _listeners
        .where((l) => l.key == null || l.key == key)
        .toList();
    if (targets.isEmpty) {
      // Its listener left while the press was on its way.
      requeue([event]);
      return;
    }
    for (final l in targets) {
      l.controller.add(event);
    }
  }
}

class _Listener<T> {
  _Listener(this.controller, this.key);

  final StreamController<T> controller;
  final String? key;
}
