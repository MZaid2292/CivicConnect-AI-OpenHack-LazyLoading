import 'dart:async';

/// Tiny reactive in-memory table used by mock repositories.
///
/// Every change re-emits a fresh unmodifiable snapshot so all screens bound to
/// the same repository instance update immediately, across roles.
class InMemoryCollection<T> {
  InMemoryCollection(Iterable<T> seed, this._idOf) : _items = [...seed];

  final List<T> _items;
  final String Function(T) _idOf;
  final _changes = StreamController<List<T>>.broadcast();

  List<T> get snapshot => List.unmodifiable(_items);

  Stream<List<T>> watch() => Stream.multi((controller) {
        controller.add(snapshot);
        final sub = _changes.stream
            .listen(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  T? find(String id) {
    for (final item in _items) {
      if (_idOf(item) == id) return item;
    }
    return null;
  }

  /// Upserts (new items go first so feeds show newest first).
  void upsert(T item, {bool notify = true}) {
    final index = _items.indexWhere((e) => _idOf(e) == _idOf(item));
    if (index == -1) {
      _items.insert(0, item);
    } else {
      _items[index] = item;
    }
    if (notify) _changes.add(snapshot);
  }

  void notify() => _changes.add(snapshot);
}
