import 'dart:async';

class LiveCollection<T> {
  LiveCollection(this._loader);

  final Future<List<T>> Function() _loader;
  final _changes = StreamController<List<T>>.broadcast();
  List<T>? _items;
  Future<void>? _inFlight;
  bool _dirty = false;

  bool get isLoaded => _items != null;
  List<T> get snapshot => List.unmodifiable(_items ?? const []);

  Stream<List<T>> watch() => Stream.multi((controller) {
        if (_items != null) {
          controller.add(snapshot);
        } else {
          refresh().catchError((Object _) {});
        }
        final sub = _changes.stream
            .listen(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  Future<List<T>> list() async {
    if (_items == null) await refresh();
    return snapshot;
  }

  Future<void> refresh() {
    if (_inFlight != null) {
      _dirty = true;
      return _inFlight!;
    }
    return _inFlight = _run();
  }

  Future<void> _run() async {
    try {
      do {
        _dirty = false;
        try {
          _items = await _loader();
          _changes.add(snapshot);
        } catch (e, st) {
          if (_items == null) _changes.addError(e, st);
          if (!_dirty) rethrow;
        }
      } while (_dirty);
    } finally {
      _inFlight = null;
    }
  }

  void clear() => _items = null;

  void emitLocal(List<T> items) {
    _items = items;
    _changes.add(snapshot);
  }
}
