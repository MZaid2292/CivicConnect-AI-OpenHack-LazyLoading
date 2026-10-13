import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_codec.dart';
import '../../../core/supabase/db_gateway.dart';
import '../../../core/supabase/live_collection.dart';
import '../domain/app_notification.dart';

/// The signed-in user's inbox. RLS limits rows to the caller; notifications
/// are created by the database workflow functions, never by the client.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._db) {
    _live = LiveCollection(_load);
  }

  final DbGateway _db;
  late final LiveCollection<AppNotification> _live;

  Future<void> refresh() => _live.refresh();
  void clear() => _live.clear();

  static AppNotification fromRow(Row n) => AppNotification(
        id: n['id'] as String,
        recipientId: n['user_id'] as String,
        title: n['title'] as String,
        body: n['body'] as String,
        at: DbCodec.time(n['created_at']),
        read: n['read_at'] != null,
      );

  Future<List<AppNotification>> _load() async => [
        for (final n in await _db.select('notifications',
            orderBy: 'created_at', limit: 200))
          fromRow(n),
      ];

  @override
  Stream<List<AppNotification>> watchFor(String recipientId) => _live.watch();

  /// Server-generated only; the client has no insert permission.
  @override
  Future<void> add(AppNotification notification) async {}

  @override
  Future<void> markAllRead(String recipientId) async {
    final me = _db.currentUserId;
    if (me == null) return;
    try {
      // Preferred: narrow function from the pending migration.
      await _db.rpc('mark_notifications_read');
    } on WorkflowException catch (e) {
      if (!e.message.contains('database update')) rethrow;
      try {
        await _db.update(
            'notifications',
            {'read_at': DateTime.now().toUtc().toIso8601String()},
            {'user_id': me},
            isNull: 'read_at');
      } on WorkflowException {
        throw const WorkflowException(
            'Marking notifications as read is not enabled on the server yet.');
      }
    }
    await _live.refresh();
  }
}
