import 'dart:async';

/// Cached, refreshable query result exposed as the repository-style stream
/// the existing view models already consume (`watchAll()`): the latest list
/// is emitted on subscribe and again after every [refresh].
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
          // Errors reach the subscriber through the stream.
          refresh().catchError((Object _) {});
        }
        final sub = _changes.stream
            .listen(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  /// Current items, loading them first if needed.
  Future<List<T>> list() async {
    if (_items == null) await refresh();
    return snapshot;
  }

  /// Reloads from the backend. Concurrent calls share one request; a call
  /// made while loading schedules exactly one follow-up reload.
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
          // Keep showing the last good data; surface errors only when there
          // is nothing to show.
          if (_items == null) _changes.addError(e, st);
          if (!_dirty) rethrow;
        }
      } while (_dirty);
    } finally {
      _inFlight = null;
    }
  }

  /// Forgets cached data (e.g. after sign-out) without notifying listeners.
  void clear() => _items = null;

  /// Replaces the cache locally (used for device-only drafts).
  void emitLocal(List<T> items) {
    _items = items;
    _changes.add(snapshot);
  }
}
