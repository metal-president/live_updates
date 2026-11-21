import 'dart:async';

/// A broadcast stream that keeps events while nobody listens.
///
/// Native code delivers taps, button presses and tokens once Dart observes
/// them; buffering here means an event that arrives between subscriptions,
/// or before the first `listen`, still reaches the next listener.
class BufferedBroadcast<T> {
  /// Creates the stream. [start] connects the native observer on first use.
  BufferedBroadcast(this._start) {
    _controller.onListen = _flush;
  }

  final void Function(void Function(T event) add) _start;
  final _controller = StreamController<T>.broadcast();
  final _buffer = <T>[];
  bool _started = false;

  /// The stream; starts the native observer on first access.
  Stream<T> get stream {
    if (!_started) {
      _started = true;
      _start(_add);
    }
    return _controller.stream;
  }

  void _add(T event) {
    if (_controller.hasListener) {
      _controller.add(event);
    } else {
      _buffer.add(event);
    }
  }

  void _flush() {
    final pending = List.of(_buffer);
    _buffer.clear();
    pending.forEach(_controller.add);
  }
}
