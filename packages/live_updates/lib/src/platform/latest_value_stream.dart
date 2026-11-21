import 'dart:async';

/// A broadcast stream that remembers its latest value and gives it to every
/// new listener first.
///
/// Push tokens are emitted by the system once per change; replaying the
/// latest one means a listener that subscribes later (or re-subscribes)
/// still learns the current token.
class LatestValueStream<T> {
  /// Creates the stream. [start] connects the native observer on first use.
  LatestValueStream(this._start);

  final void Function(void Function(T value) add) _start;
  final _controller = StreamController<T>.broadcast();
  T? _latest;
  bool _hasLatest = false;
  bool _started = false;

  /// The stream; starts the native observer on first access.
  Stream<T> get stream {
    if (!_started) {
      _started = true;
      _start(_add);
    }
    return Stream<T>.multi((listener) {
      if (_hasLatest) listener.add(_latest as T);
      final sub = _controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener
        ..onCancel = sub.cancel
        ..onPause = sub.pause
        ..onResume = sub.resume;
    });
  }

  void _add(T value) {
    _latest = value;
    _hasLatest = true;
    _controller.add(value);
  }

  /// Stops delivering values; listeners get a done event.
  Future<void> close() => _controller.close();
}
