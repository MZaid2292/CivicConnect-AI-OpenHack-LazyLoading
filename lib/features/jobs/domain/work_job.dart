import 'package:equatable/equatable.dart';

import '../../../core/models/media_attachment.dart';
import '../../complaints/domain/complaint.dart';

/// Contract (work order) lifecycle — independent from complaint status.
enum JobStatus {
  openForBids,
  awarded,
  inProgress,
  completionSubmitted,
  reworkRequested,
  completed,
  cancelled,
}

extension JobStatusInfo on JobStatus {
  String get label => switch (this) {
        JobStatus.openForBids => 'Open for bids',
        JobStatus.awarded => 'Awarded',
        JobStatus.inProgress => 'In progress',
        JobStatus.completionSubmitted => 'Completion submitted',
        JobStatus.reworkRequested => 'Rework requested',
        JobStatus.completed => 'Completed',
        JobStatus.cancelled => 'Cancelled',
      };

  bool get isActive => {
        JobStatus.awarded,
        JobStatus.inProgress,
        JobStatus.completionSubmitted,
        JobStatus.reworkRequested,
      }.contains(this);
}

/// SIMULATED payment state. No money moves; there is no payment gateway.
enum PaymentStatus { notStarted, heldSimulated, releasedSimulated }

extension PaymentStatusInfo on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.notStarted => 'Not started',
        PaymentStatus.heldSimulated => 'Held (simulation)',
        PaymentStatus.releasedSimulated => 'Released (simulation)',
      };
}

class Bid extends Equatable {
  const Bid({
    required this.id,
    required this.contractorId,
    required this.contractorName,
    required this.amount,
    required this.days,
    required this.note,
    required this.at,
  });
  final String id;
  final String contractorId;
  final String contractorName;
  final int amount;
  final int days;
  final String note;
  final DateTime at;

  @override
  List<Object?> get props => [id, contractorId, amount, days, note, at];
}

class ProgressLog extends Equatable {
  const ProgressLog({
    required this.id,
    required this.note,
    required this.at,
    required this.authorName,
    this.photo,
  });
  final String id;
  final String note;
  final DateTime at;
  final String authorName;
  final MediaAttachment? photo;

  @override
  List<Object?> get props => [id, note, at, authorName, photo];
}

class WorkJob extends Equatable {
  const WorkJob({
    required this.id,
    required this.complaintId,
    required this.title,
    required this.category,
    required this.department,
    required this.budgetEstimate,
    required this.status,
    required this.createdAt,
    this.bids = const [],
    this.contractorId,
    this.contractorName,
    this.awardedAmount,
    this.progressLogs = const [],
    this.beforePhotos = const [],
    this.afterPhotos = const [],
    this.inspectionNote,
    this.paymentStatus = PaymentStatus.notStarted,
    this.completedAt,
  });

  final String id;
  final String complaintId;
  final String title;
  final ComplaintCategory category;
  final String department;
  final int budgetEstimate;
  final JobStatus status;
  final DateTime createdAt;
  final List<Bid> bids;
  final String? contractorId;
  final String? contractorName;
  final int? awardedAmount;
  final List<ProgressLog> progressLogs;
  final List<MediaAttachment> beforePhotos;
  final List<MediaAttachment> afterPhotos;
  final String? inspectionNote;
  final PaymentStatus paymentStatus;
  final DateTime? completedAt;

  bool hasBidFrom(String contractorId) =>
      bids.any((b) => b.contractorId == contractorId);

  WorkJob copyWith({
    JobStatus? status,
    List<Bid>? bids,
    String? contractorId,
    String? contractorName,
    int? awardedAmount,
    List<ProgressLog>? progressLogs,
    List<MediaAttachment>? beforePhotos,
    List<MediaAttachment>? afterPhotos,
    String? inspectionNote,
    PaymentStatus? paymentStatus,
    DateTime? completedAt,
  }) =>
      WorkJob(
        id: id,
        complaintId: complaintId,
        title: title,
        category: category,
        department: department,
        budgetEstimate: budgetEstimate,
        status: status ?? this.status,
        createdAt: createdAt,
        bids: bids ?? this.bids,
        contractorId: contractorId ?? this.contractorId,
        contractorName: contractorName ?? this.contractorName,
        awardedAmount: awardedAmount ?? this.awardedAmount,
        progressLogs: progressLogs ?? this.progressLogs,
        beforePhotos: beforePhotos ?? this.beforePhotos,
        afterPhotos: afterPhotos ?? this.afterPhotos,
        inspectionNote: inspectionNote ?? this.inspectionNote,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        completedAt: completedAt ?? this.completedAt,
      );

  @override
  List<Object?> get props => [
        id,
        complaintId,
        title,
        category,
        department,
        budgetEstimate,
        status,
        createdAt,
        bids,
        contractorId,
        contractorName,
        awardedAmount,
        progressLogs,
        beforePhotos,
        afterPhotos,
        inspectionNote,
        paymentStatus,
        completedAt,
      ];
}
