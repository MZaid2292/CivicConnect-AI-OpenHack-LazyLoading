import 'package:uuid/uuid.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/models/media_attachment.dart';
import '../../../../core/models/permissions.dart';
import '../../../../core/models/workflow_exception.dart';
import '../../../../core/utils/geo.dart';
import '../../../jobs/domain/job_repositories.dart';
import '../../../notifications/domain/app_notification.dart';
import '../complaint.dart';
import '../complaint_repository.dart';
import '../complaint_workflow.dart';
import '../priority_rules_repository.dart';
import 'category_classifier.dart';
import 'duplicate_detector.dart';
import 'priority_engine.dart';

/// Form data for creating or editing a complaint.
class ComplaintInput {
  const ComplaintInput({
    required this.title,
    required this.description,
    required this.category,
    required this.address,
    this.location,
    this.locationSource = LocationSource.none,
    this.photos = const [],
  });
  final String title;
  final String description;
  final ComplaintCategory category;
  final String address;
  final GeoPoint? location;
  final LocationSource locationSource;
  final List<MediaAttachment> photos;
}

/// Field-level validation shared by the form view model and the service.
class ComplaintValidator {
  const ComplaintValidator._();
  static String? title(String v) => v.trim().length < 8
      ? 'Give a short, specific title (at least 8 characters).'
      : null;
  static String? description(String v) => v.trim().length < 20
      ? 'Describe the issue in at least 20 characters.'
      : null;
  static String? address(String v) => v.trim().length < 4
      ? 'Add a landmark or street so crews can find it.'
      : null;
}

/// Complaint use cases: submission, NLP helpers, support, verification,
/// duplicates, feedback and priority recalculation.
class ComplaintService {
  ComplaintService({
    required ComplaintRepository complaints,
    required PriorityRulesRepository rules,
    required ContractorRepository contractors,
    required NotificationRepository notifications,
    this.classifier = const KeywordCategoryClassifier(),
    this.duplicateDetector = const DuplicateDetector(),
    this.priorityEngine = const PriorityEngine(),
    DateTime Function()? clock,
  })  : _complaints = complaints,
        _rules = rules,
        _contractors = contractors,
        _notifications = notifications,
        _clock = clock ?? DateTime.now;

  final ComplaintRepository _complaints;
  final PriorityRulesRepository _rules;
  final ContractorRepository _contractors;
  final NotificationRepository _notifications;
  final KeywordCategoryClassifier classifier;
  final DuplicateDetector duplicateDetector;
  final PriorityEngine priorityEngine;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  DateTime get now => _clock();
  PriorityRules get rules => _rules.current;

  // ---- Algorithms exposed to view models -------------------------------

  ClassificationResult classify(String title, String description) =>
      classifier.classify(title, description);

  Future<List<DuplicateCandidate>> findDuplicates({
    required String title,
    required String description,
    required ComplaintCategory category,
    required GeoPoint? location,
    String? excludeId,
  }) async =>
      duplicateDetector.findPotentialDuplicates(
        title: title,
        description: description,
        category: category,
        location: location,
        existing: await _complaints.listComplaints(),
        excludeId: excludeId,
      );

  PriorityAssessment previewPriority(
          {required ComplaintCategory category,
          required String title,
          required String description}) =>
      priorityEngine.assess(
        category: category,
        title: title,
        description: description,
        supportCount: 0,
        createdAt: now,
        now: now,
        rules: rules,
      );

  // ---- Citizen use cases -------------------------------------------------

  Future<Complaint> saveDraft(Actor actor, ComplaintInput input,
      {String? draftId}) async {
    requireRole(actor, {AppRole.citizen}, 'save complaint drafts');
    final existing = draftId == null ? null : await _ownedDraft(actor, draftId);
    final draft = _build(actor, input,
        id: existing?.id ?? await _complaints.nextId(),
        status: ComplaintStatus.draft,
        createdAt: existing?.createdAt ?? now,
        timeline: const []);
    await _complaints.save(draft);
    return draft;
  }

  Future<Complaint> submit(Actor actor, ComplaintInput input,
      {String? draftId}) async {
    requireRole(actor, {AppRole.citizen}, 'submit complaints');
    final error = ComplaintValidator.title(input.title) ??
        ComplaintValidator.description(input.description) ??
        ComplaintValidator.address(input.address);
    if (error != null) throw WorkflowException(error);

    final existing = draftId == null ? null : await _ownedDraft(actor, draftId);
    if (existing != null) {
      ComplaintWorkflow.ensure(
          existing.status, ComplaintStatus.submitted, actor.role);
    }
    final complaint = _build(actor, input,
        id: existing?.id ?? await _complaints.nextId(),
        status: ComplaintStatus.submitted,
        createdAt: now,
        timeline: [
          TimelineEvent(
              status: ComplaintStatus.submitted,
              at: now,
              actorName: actor.name,
              actorRole: actor.role,
              note: input.photos.isEmpty ? 'Submitted without photos.' : null),
        ]);
    await _complaints.save(complaint);
    return complaint;
  }

  Future<void> toggleSupport(Actor actor, String complaintId) async {
    requireRole(actor, {AppRole.citizen}, 'support reports');
    final c = await _require(complaintId);
    if (!c.status.isOpen) {
      throw const WorkflowException('Only open reports can be supported.');
    }
    if (c.reporterId == actor.id) {
      throw const WorkflowException('You reported this issue already.');
    }
    final supporters = {...c.supporterIds};
    supporters.contains(actor.id)
        ? supporters.remove(actor.id)
        : supporters.add(actor.id);
    await _saveRescored(c.copyWith(supporterIds: supporters));
  }

  Future<void> addComment(Actor actor, String complaintId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const WorkflowException('Comment is empty.');
    if (trimmed.length > 500) {
      throw const WorkflowException('Keep comments under 500 characters.');
    }
    final c = await _require(complaintId);
    if (c.status == ComplaintStatus.draft) {
      throw const WorkflowException('Drafts cannot receive comments.');
    }
    await _complaints.save(c.copyWith(comments: [
      ...c.comments,
      ComplaintComment(
          id: _uuid.v4(),
          authorName: actor.name,
          authorRole: actor.role,
          text: trimmed,
          at: now),
    ]));
  }

  Future<void> rateResolution(
      Actor actor, String complaintId, int rating, String comment) async {
    requireRole(actor, {AppRole.citizen}, 'rate resolutions');
    final c = await _require(complaintId);
    if (c.reporterId != actor.id) {
      throw const WorkflowException('Only the reporter can rate this work.');
    }
    if (c.status != ComplaintStatus.resolved) {
      throw const WorkflowException('You can rate once the issue is resolved.');
    }
    if (c.feedback != null) {
      throw const WorkflowException('Feedback was already submitted.');
    }
    if (rating < 1 || rating > 5) {
      throw const WorkflowException('Choose 1 to 5 stars.');
    }
    await _complaints.save(c.copyWith(
        feedback:
            CitizenFeedback(rating: rating, comment: comment.trim(), at: now)));
    if (c.contractorId != null) {
      final contractor = await _contractors.findById(c.contractorId!);
      if (contractor != null) {
        await _contractors.save(contractor.copyWith(
            ratingTotal: contractor.ratingTotal + rating,
            ratingCount: contractor.ratingCount + 1));
      }
    }
  }

  // ---- Admin use cases ---------------------------------------------------

  Future<void> verify(Actor actor, String complaintId,
      {required String department, String? note}) async {
    final c = await _require(complaintId);
    ComplaintWorkflow.ensure(c.status, ComplaintStatus.verified, actor.role);
    await _transition(
        actor, c.copyWith(department: department), ComplaintStatus.verified,
        note: note?.trim().isNotEmpty == true
            ? note!.trim()
            : 'Verified. Routed to $department.');
  }

  Future<void> reject(Actor actor, String complaintId, String reason) async {
    if (reason.trim().length < 5) {
      throw const WorkflowException('Give the citizen a clear reason.');
    }
    final c = await _require(complaintId);
    ComplaintWorkflow.ensure(c.status, ComplaintStatus.rejected, actor.role);
    await _transition(actor, c.copyWith(rejectionReason: reason.trim()),
        ComplaintStatus.rejected,
        note: reason.trim());
  }

  /// Merges [duplicateId] into [originalId]; supporters carry over.
  Future<void> markDuplicate(
      Actor actor, String duplicateId, String originalId) async {
    if (duplicateId == originalId) {
      throw const WorkflowException('A report cannot duplicate itself.');
    }
    final dup = await _require(duplicateId);
    final original = await _require(originalId);
    ComplaintWorkflow.ensure(dup.status, ComplaintStatus.duplicate, actor.role);
    if (!original.status.isOpen &&
        original.status != ComplaintStatus.resolved) {
      throw const WorkflowException('Merge into an open or resolved report.');
    }
    await _transition(actor, dup.copyWith(duplicateOfId: originalId),
        ComplaintStatus.duplicate,
        note: 'Merged into $originalId. Your support was carried over.');
    await _saveRescored(original.copyWith(
        supporterIds: {
      ...original.supporterIds,
      ...dup.supporterIds,
      dup.reporterId,
    }..remove(original.reporterId)));
  }

  Future<void> clearDuplicateFlag(Actor actor, String complaintId) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'review duplicates');
    final c = await _require(complaintId);
    await _complaints.save(c.copyWith(duplicateReviewCleared: true));
  }

  /// Moves a complaint along the work lifecycle (used by the job service).
  /// Enforces the state machine and the actor's role.
  Future<void> advanceForWork(
      Actor actor, String complaintId, ComplaintStatus to,
      {String? note, String? contractorId, String? jobId}) async {
    final c = await _require(complaintId);
    ComplaintWorkflow.ensure(c.status, to, actor.role);
    await _transition(
        actor, c.copyWith(contractorId: contractorId, jobId: jobId), to,
        note: note);
  }

  /// Links a newly opened tender to the complaint without a status change.
  Future<void> linkJob(Actor actor, String complaintId, String jobId) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'open tenders');
    final c = await _require(complaintId);
    await _complaints.save(c.copyWith(jobId: jobId));
  }

  Future<Complaint?> findById(String id) => _complaints.findById(id);

  Future<void> updatePriorityRules(Actor actor, PriorityRules newRules) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'change priority rules');
    await _rules.save(newRules);
    await recomputePriorities();
  }

  Future<void> recomputePriorities() async {
    final all = await _complaints.listComplaints();
    await _complaints.saveAll(all.map((c) =>
        c.copyWith(priority: priorityEngine.assessComplaint(c, rules, now))));
  }

  /// Potential duplicates among open, unreviewed reports (admin queue).
  Future<Map<Complaint, List<DuplicateCandidate>>>
      duplicateReviewQueue() async {
    final all = await _complaints.listComplaints();
    final result = <Complaint, List<DuplicateCandidate>>{};
    for (final c in all.where((c) =>
        (c.status == ComplaintStatus.submitted ||
            c.status == ComplaintStatus.verified) &&
        !c.duplicateReviewCleared)) {
      final matches = duplicateDetector
          .findPotentialDuplicates(
            title: c.title,
            description: c.description,
            category: c.category,
            location: c.location,
            existing: all,
            excludeId: c.id,
          )
          // Only flag the newer report of a pair.
          .where((m) => m.complaint.createdAt.isBefore(c.createdAt))
          .toList();
      if (matches.isNotEmpty) result[c] = matches;
    }
    return result;
  }

  // ---- Helpers -------------------------------------------------------------

  Complaint _build(Actor actor, ComplaintInput input,
      {required String id,
      required ComplaintStatus status,
      required DateTime createdAt,
      required List<TimelineEvent> timeline}) {
    final classification = classify(input.title, input.description);
    return Complaint(
      id: id,
      title: input.title.trim(),
      description: input.description.trim(),
      category: input.category,
      status: status,
      address: input.address.trim(),
      reporterId: actor.id,
      reporterName: actor.name,
      createdAt: createdAt,
      location: input.location,
      locationSource: input.locationSource,
      photos: input.photos,
      timeline: timeline,
      classification: classification,
      priority: priorityEngine.assess(
        category: input.category,
        title: input.title,
        description: input.description,
        supportCount: 0,
        createdAt: createdAt,
        now: now,
        rules: rules,
      ),
    );
  }

  Future<Complaint> _require(String id) async {
    final c = await _complaints.findById(id);
    if (c == null) throw WorkflowException('Report $id was not found.');
    return c;
  }

  Future<Complaint> _ownedDraft(Actor actor, String id) async {
    final c = await _require(id);
    if (c.reporterId != actor.id || c.status != ComplaintStatus.draft) {
      throw const WorkflowException('Only your own drafts can be edited.');
    }
    return c;
  }

  Future<void> _saveRescored(Complaint c) => _complaints.save(
      c.copyWith(priority: priorityEngine.assessComplaint(c, rules, now)));

  Future<void> _transition(Actor actor, Complaint c, ComplaintStatus to,
      {String? note}) async {
    await _complaints.save(c.copyWith(status: to, timeline: [
      ...c.timeline,
      TimelineEvent(
          status: to,
          at: now,
          actorName: actor.name,
          actorRole: actor.role,
          note: note),
    ]));
    await _notifications.add(AppNotification(
      id: _uuid.v4(),
      recipientId: c.reporterId,
      title: '${c.id} is now ${to.label}',
      body: note ?? c.title,
      at: now,
      complaintId: c.id,
    ));
  }
}
