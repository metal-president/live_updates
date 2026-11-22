import 'dart:async';

/// Button presses from a native observer that is connected only while
/// someone listens.
///
/// While nobody listens, native code keeps the presses and runs the
/// background action handler for them. A listener may accept only some
/// events (one update's presses): an event that no current listener accepts
/// waits here for one that does, and is handed back to native code when the
/// last listener cancels, so it still reaches the background handler.
class ObservedBroadcast<T> {
  /// Creates the stream. [attach] connects the native observer; [detach]
  /// disconnects it and queues the unhandled events natively again.
  ObservedBroadcast({required this.attach, required this.detach});

  /// Connects the native observer, which calls `add` for every event.
  final void Function(void Function(T event) add) attach;

  /// Disconnects the native observer and hands back unhandled events.
  final void Function(List<T> unhandled) detach;

  final _listeners = <_Listener<T>>[];
  final _held = <T>[];
  bool _attached = false;

  /// Events that [accepts] (all when `null`).
  Stream<T> stream([bool Function(T event)? accepts]) {
    late final _Listener<T> listener;
    final controller = StreamController<T>.broadcast();
    listener = _Listener(controller, accepts);
    controller
      ..onListen = (() => _addListener(listener))
      ..onCancel = (() => _removeListener(listener));
    return controller.stream;
  }

  void _addListener(_Listener<T> listener) {
    _listeners.add(listener);
    final held = _held.where(listener.wants).toList();
    _held.removeWhere(listener.wants);
    held.forEach(listener.controller.add);
    if (!_attached) {
      _attached = true;
      attach(_deliver);
    }
  }

  void _removeListener(_Listener<T> listener) {
    _listeners.remove(listener);
    if (_listeners.isNotEmpty || !_attached) return;
    _attached = false;
    final unhandled = List.of(_held);
    _held.clear();
    detach(unhandled);
  }

  void _deliver(T event) {
    if (!_attached) {
      // Arrived after the last listener left: back to native code.
      detach([event]);
      return;
    }
    final targets = _listeners.where((l) => l.wants(event)).toList();
    if (targets.isEmpty) {
      _held.add(event);
    } else {
      for (final l in targets) {
        l.controller.add(event);
      }
    }
  }
}

class _Listener<T> {
  _Listener(this.controller, this.accepts);

  final StreamController<T> controller;
  final bool Function(T event)? accepts;

  bool wants(T event) => accepts?.call(event) ?? true;
}
