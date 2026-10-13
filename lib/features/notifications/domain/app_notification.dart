import 'package:equatable/equatable.dart';

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.title,
    required this.body,
    required this.at,
    this.complaintId,
    this.jobId,
    this.read = false,
  });

  final String id;
  final String recipientId;
  final String title;
  final String body;
  final DateTime at;
  final String? complaintId;
  final String? jobId;
  final bool read;

  AppNotification markRead() => AppNotification(
        id: id,
        recipientId: recipientId,
        title: title,
        body: body,
        at: at,
        complaintId: complaintId,
        jobId: jobId,
        read: true,
      );

  @override
  List<Object?> get props =>
      [id, recipientId, title, body, at, complaintId, jobId, read];
}

/// In-app notification inbox. Push delivery (FCM / local notifications) is a
/// later integration; this only powers the in-app list.
abstract class NotificationRepository {
  Stream<List<AppNotification>> watchFor(String recipientId);
  Future<void> add(AppNotification notification);
  Future<void> markAllRead(String recipientId);
}
