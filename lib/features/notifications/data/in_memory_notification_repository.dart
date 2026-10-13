import '../../../core/data/in_memory_collection.dart';
import '../domain/app_notification.dart';

class InMemoryNotificationRepository implements NotificationRepository {
  InMemoryNotificationRepository([Iterable<AppNotification> seed = const []])
      : _store = InMemoryCollection(seed, (n) => n.id);

  final InMemoryCollection<AppNotification> _store;

  @override
  Stream<List<AppNotification>> watchFor(String recipientId) => _store
      .watch()
      .map((all) => all.where((n) => n.recipientId == recipientId).toList());

  @override
  Future<void> add(AppNotification notification) async =>
      _store.upsert(notification);

  @override
  Future<void> markAllRead(String recipientId) async {
    for (final n in _store.snapshot) {
      if (n.recipientId == recipientId && !n.read) {
        _store.upsert(n.markRead(), notify: false);
      }
    }
    _store.notify();
  }
}
