import 'package:equatable/equatable.dart';

import '../../../core/models/app_role.dart';
import '../../../core/models/media_attachment.dart';
import '../../../core/utils/geo.dart';
import 'services/category_classifier.dart';
import 'services/priority_engine.dart';

enum ComplaintCategory { roadDamage, streetlight, garbage, drainage, other }

extension ComplaintCategoryInfo on ComplaintCategory {
  String get label => switch (this) {
        ComplaintCategory.roadDamage => 'Potholes & road damage',
        ComplaintCategory.streetlight => 'Streetlights',
        ComplaintCategory.garbage => 'Garbage & waste',
        ComplaintCategory.drainage => 'Water & drainage',
        ComplaintCategory.other => 'Other',
      };

  String get shortLabel => switch (this) {
        ComplaintCategory.roadDamage => 'Roads',
        ComplaintCategory.streetlight => 'Streetlights',
        ComplaintCategory.garbage => 'Waste',
        ComplaintCategory.drainage => 'Drainage',
        ComplaintCategory.other => 'Other',
      };

  /// Default municipal department responsible for this category.
  String get department => switch (this) {
        ComplaintCategory.roadDamage => 'Roads & Infrastructure',
        ComplaintCategory.streetlight => 'Electrical Services',
        ComplaintCategory.garbage => 'Sanitation',
        ComplaintCategory.drainage => 'Water & Sewerage',
        ComplaintCategory.other => 'General Services',
      };
}

/// Complaint lifecycle. Contract/payment state lives on `WorkJob` instead.
enum ComplaintStatus {
  draft,
  submitted,
  verified,
  assigned,
  inProgress,
  awaitingInspection,
  reworkRequired,
  resolved,
  rejected,
  duplicate,
}

extension ComplaintStatusInfo on ComplaintStatus {
  String get label => switch (this) {
        ComplaintStatus.draft => 'Draft',
        ComplaintStatus.submitted => 'Submitted',
        ComplaintStatus.verified => 'Verified',
        ComplaintStatus.assigned => 'Assigned',
        ComplaintStatus.inProgress => 'In progress',
        ComplaintStatus.awaitingInspection => 'Awaiting inspection',
        ComplaintStatus.reworkRequired => 'Rework required',
        ComplaintStatus.resolved => 'Resolved',
        ComplaintStatus.rejected => 'Rejected',
        ComplaintStatus.duplicate => 'Merged duplicate',
      };

  bool get isOpen => !{
        ComplaintStatus.draft,
        ComplaintStatus.resolved,
        ComplaintStatus.rejected,
        ComplaintStatus.duplicate,
      }.contains(this);

  bool get isPublic => this != ComplaintStatus.draft;
}

enum LocationSource { gps, manualPin, defaultArea, none }

extension LocationSourceInfo on LocationSource {
  String get label => switch (this) {
        LocationSource.gps => 'Device GPS (approximate)',
        LocationSource.manualPin => 'Pinned on map',
        LocationSource.defaultArea => 'Ward centre (approximate)',
        LocationSource.none => 'Address only',
      };
}

class TimelineEvent extends Equatable {
  const TimelineEvent({
    required this.status,
    required this.at,
    required this.actorName,
    required this.actorRole,
    this.note,
  });
  final ComplaintStatus status;
  final DateTime at;
  final String actorName;
  final AppRole actorRole;
  final String? note;

  @override
  List<Object?> get props => [status, at, actorName, actorRole, note];
}

class ComplaintComment extends Equatable {
  const ComplaintComment({
    required this.id,
    required this.authorName,
    required this.authorRole,
    required this.text,
    required this.at,
  });
  final String id;
  final String authorName;
  final AppRole authorRole;
  final String text;
  final DateTime at;

  @override
  List<Object?> get props => [id, authorName, authorRole, text, at];
}

class CitizenFeedback extends Equatable {
  const CitizenFeedback(
      {required this.rating, required this.comment, required this.at});
  final int rating;
  final String comment;
  final DateTime at;

  @override
  List<Object?> get props => [rating, comment, at];
}

class Complaint extends Equatable {
  const Complaint({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.address,
    required this.reporterId,
    required this.reporterName,
    required this.createdAt,
    required this.priority,
    this.location,
    this.locationSource = LocationSource.none,
    this.photos = const [],
    this.supporterIds = const {},
    this.comments = const [],
    this.timeline = const [],
    this.classification,
    this.department,
    this.contractorId,
    this.jobId,
    this.feedback,
    this.duplicateOfId,
    this.rejectionReason,
    this.duplicateReviewCleared = false,
  });

  final String id;
  final String title;
  final String description;
  final ComplaintCategory category;
  final ComplaintStatus status;
  final String address;
  final String reporterId;
  final String reporterName;
  final DateTime createdAt;
  final PriorityAssessment priority;
  final GeoPoint? location;
  final LocationSource locationSource;
  final List<MediaAttachment> photos;
  final Set<String> supporterIds;
  final List<ComplaintComment> comments;
  final List<TimelineEvent> timeline;

  /// The rule-based suggestion shown at submission time (kept for audit).
  final ClassificationResult? classification;
  final String? department;
  final String? contractorId;
  final String? jobId;
  final CitizenFeedback? feedback;
  final String? duplicateOfId;
  final String? rejectionReason;

  /// Admin reviewed potential duplicates and decided this report is distinct.
  final bool duplicateReviewCleared;

  int get supportCount => supporterIds.length;

  DateTime get updatedAt => timeline.isEmpty ? createdAt : timeline.last.at;

  bool get categoryOverridden =>
      classification?.top != null && classification!.top!.category != category;

  Complaint copyWith({
    String? title,
    String? description,
    ComplaintCategory? category,
    ComplaintStatus? status,
    String? address,
    DateTime? createdAt,
    PriorityAssessment? priority,
    GeoPoint? location,
    bool clearLocation = false,
    LocationSource? locationSource,
    List<MediaAttachment>? photos,
    Set<String>? supporterIds,
    List<ComplaintComment>? comments,
    List<TimelineEvent>? timeline,
    ClassificationResult? classification,
    String? department,
    String? contractorId,
    String? jobId,
    CitizenFeedback? feedback,
    String? duplicateOfId,
    String? rejectionReason,
    bool? duplicateReviewCleared,
  }) =>
      Complaint(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        status: status ?? this.status,
        address: address ?? this.address,
        reporterId: reporterId,
        reporterName: reporterName,
        createdAt: createdAt ?? this.createdAt,
        priority: priority ?? this.priority,
        location: clearLocation ? null : (location ?? this.location),
        locationSource: locationSource ?? this.locationSource,
        photos: photos ?? this.photos,
        supporterIds: supporterIds ?? this.supporterIds,
        comments: comments ?? this.comments,
        timeline: timeline ?? this.timeline,
        classification: classification ?? this.classification,
        department: department ?? this.department,
        contractorId: contractorId ?? this.contractorId,
        jobId: jobId ?? this.jobId,
        feedback: feedback ?? this.feedback,
        duplicateOfId: duplicateOfId ?? this.duplicateOfId,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        duplicateReviewCleared:
            duplicateReviewCleared ?? this.duplicateReviewCleared,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        category,
        status,
        address,
        reporterId,
        createdAt,
        priority,
        location,
        locationSource,
        photos,
        supporterIds,
        comments,
        timeline,
        classification,
        department,
        contractorId,
        jobId,
        feedback,
        duplicateOfId,
        rejectionReason,
        duplicateReviewCleared,
      ];
}
