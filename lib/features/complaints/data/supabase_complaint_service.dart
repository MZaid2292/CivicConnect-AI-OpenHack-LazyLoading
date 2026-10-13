import 'package:uuid/uuid.dart';

import '../../../core/models/app_role.dart';
import '../../../core/models/permissions.dart';
import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_codec.dart';
import '../../../core/supabase/db_gateway.dart';
import '../../../core/supabase/media_store.dart';
import '../../../core/utils/text_similarity.dart';
import '../../auth/domain/auth_repository.dart';
import '../../jobs/data/supabase_job_repositories.dart';
import '../domain/complaint.dart';
import '../domain/priority_rules_repository.dart';
import '../domain/services/complaint_service.dart';
import '../domain/services/duplicate_detector.dart';
import '../domain/services/priority_engine.dart';
import 'supabase_complaint_repository.dart';

/// Complaint use cases against Supabase. State changes go through the
/// SECURITY DEFINER workflow functions (review_complaint, review_duplicate,
/// save_priority_rule); citizen-owned rows (complaint, photos, comments,
/// support, reviews) are inserted directly under RLS. The client-side checks
/// inherited from [ComplaintService] only keep the UI responsive — the
/// database is the authority.
class SupabaseComplaintService extends ComplaintService {
  SupabaseComplaintService({
    required SupabaseComplaintRepository complaints,
    required super.rules,
    required super.contractors,
    required super.notifications,
    required SupabaseJobRepository jobs,
    required DbGateway db,
    required MediaStore media,
    required UserProfile? Function() profile,
  })  : _repo = complaints,
        _rulesRepo = rules,
        _jobRepo = jobs,
        _db = db,
        _media = media,
        _profile = profile,
        super(complaints: complaints);

  final SupabaseComplaintRepository _repo;
  final PriorityRulesRepository _rulesRepo;
  final SupabaseJobRepository _jobRepo;
  final DbGateway _db;
  final MediaStore _media;
  final UserProfile? Function() _profile;
  static const _uuid = Uuid();

  String get _me {
    final id = _db.currentUserId;
    if (id == null) throw const WorkflowException('Sign in again.');
    return id;
  }

  // ---- Citizen ---------------------------------------------------------------

  @override
  Future<Complaint> submit(Actor actor, ComplaintInput input,
      {String? draftId}) async {
    requireRole(actor, {AppRole.citizen}, 'submit complaints');
    final error = ComplaintValidator.title(input.title) ??
        ComplaintValidator.description(input.description) ??
        ComplaintValidator.address(input.address);
    if (error != null) throw WorkflowException(error);
    final location = input.location;
    if (location == null) {
      throw const WorkflowException(
          'Add the location: use your location, pin it on the map, or use '
          'the ward centre.');
    }
    final municipality = await _municipalityForSubmission();
    // Validate photos before creating anything.
    final photos = [
      for (final p in input.photos)
        if (p.bytes != null) (p, PhotoRules.detect(p.bytes!)),
    ];

    final row = await _db.insert('complaints', {
      'citizen_id': _me,
      'municipality_id': municipality,
      'title': input.title.trim(),
      'description': input.description.trim(),
      'category': DbCodec.category(input.category),
      'latitude': location.latitude,
      'longitude': location.longitude,
      'approximate_address': input.address.trim(),
    });
    final complaintUuid = row['id'] as String;
    final reference = row['reference_code'] as String;
    if (draftId != null) _repo.removeDraft(draftId);

    // Storage paths depend on the complaint uuid, so photos go second.
    var failed = 0;
    for (final (photo, (mime, ext)) in photos) {
      final path = 'complaints/$complaintUuid/${_uuid.v4()}.$ext';
      try {
        await _media.upload(complaintImagesBucket, path, photo.bytes!,
            contentType: mime);
        await _db.insert('complaint_images', {
          'complaint_id': complaintUuid,
          'uploaded_by': _me,
          'storage_path': path,
          'kind': 'report',
        });
      } on WorkflowException {
        failed++;
      }
    }
    await _repo.refresh();
    final created = await _repo.findById(reference);
    if (created == null) {
      throw WorkflowException('$reference was submitted but could not be '
          'loaded. Pull to refresh.');
    }
    if (failed > 0) {
      throw PartialSubmitException(
          created,
          '$reference was submitted, but $failed of ${photos.length} '
          'photo${photos.length == 1 ? '' : 's'} could not be uploaded.');
    }
    return created;
  }

  Future<String> _municipalityForSubmission() async {
    final own = _profile()?.municipalityId;
    if (own != null) return own;
    // Single-municipality deployments: the only municipality is unambiguous.
    final all = await _db.select('municipalities', columns: 'id', limit: 2);
    if (all.length == 1) return all.first['id'] as String;
    throw const WorkflowException(
        'Your account is not linked to a municipality yet, so the report '
        'cannot be routed. Contact your municipality.');
  }

  @override
  Future<void> toggleSupport(Actor actor, String complaintId) async {
    requireRole(actor, {AppRole.citizen}, 'support reports');
    final c = await _require(complaintId);
    if (!c.status.isOpen) {
      throw const WorkflowException('Only open reports can be supported.');
    }
    if (c.reporterId == _me) {
      throw const WorkflowException('You reported this issue already.');
    }
    final uuid = await _repo.requireUuid(complaintId);
    if (c.supporterIds.contains(_me)) {
      await _db
          .delete('complaint_support', {'complaint_id': uuid, 'user_id': _me});
    } else {
      await _db
          .insert('complaint_support', {'complaint_id': uuid, 'user_id': _me});
    }
    await _repo.refresh();
  }

  @override
  Future<void> addComment(Actor actor, String complaintId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const WorkflowException('Comment is empty.');
    if (trimmed.length > 500) {
      throw const WorkflowException('Keep comments under 500 characters.');
    }
    final uuid = await _repo.requireUuid(complaintId);
    await _db.insert('complaint_comments',
        {'complaint_id': uuid, 'user_id': _me, 'body': trimmed});
    await _repo.refresh();
  }

  @override
  Future<void> rateResolution(
      Actor actor, String complaintId, int rating, String comment) async {
    requireRole(actor, {AppRole.citizen}, 'rate resolutions');
    final c = await _require(complaintId);
    if (c.status != ComplaintStatus.resolved) {
      throw const WorkflowException('You can rate once the issue is resolved.');
    }
    if (c.feedback != null) {
      throw const WorkflowException('Feedback was already submitted.');
    }
    if (rating < 1 || rating > 5) {
      throw const WorkflowException('Choose 1 to 5 stars.');
    }
    if (c.jobId == null) {
      throw const WorkflowException('No repair contract to rate.');
    }
    await _db.insert('reviews', {
      'complaint_id': await _repo.requireUuid(complaintId),
      'contract_id': await _jobRepo.requireContractId(c.jobId!),
      'citizen_id': _me,
      'rating': rating,
      'feedback': comment.trim().isEmpty ? null : comment.trim(),
    });
    await _repo.refresh();
  }

  // ---- Municipal admin ---------------------------------------------------------

  @override
  Future<void> verify(Actor actor, String complaintId,
      {required String department, String? note}) async {
    await _db.rpc('review_complaint', {
      'p_complaint_id': await _repo.requireUuid(complaintId),
      'p_new_status': 'verified',
      'p_remarks': note?.trim().isNotEmpty == true
          ? note!.trim()
          : 'Verified. Routed to $department.',
    });
    await _repo.refresh();
  }

  @override
  Future<void> reject(Actor actor, String complaintId, String reason) async {
    if (reason.trim().length < 5) {
      throw const WorkflowException('Give the citizen a clear reason.');
    }
    await _db.rpc('review_complaint', {
      'p_complaint_id': await _repo.requireUuid(complaintId),
      'p_new_status': 'rejected',
      'p_remarks': reason.trim(),
    });
    await _repo.refresh();
  }

  /// Only pairs flagged by the database duplicate check can be merged.
  @override
  Future<void> markDuplicate(
      Actor actor, String duplicateId, String originalId) async {
    if (duplicateId == originalId) {
      throw const WorkflowException('A report cannot duplicate itself.');
    }
    final dup = await _repo.requireUuid(duplicateId);
    final original = await _repo.requireUuid(originalId);
    final candidates = await _db.select('duplicate_candidates', eq: {
      'complaint_id': dup,
      'candidate_id': original,
      'review_status': 'pending',
    });
    if (candidates.isEmpty) {
      throw WorkflowException('$duplicateId and $originalId were not flagged '
          'as possible duplicates by the server, so they cannot be merged.');
    }
    await _db.rpc('review_duplicate', {
      'p_candidate_id': candidates.first['id'],
      'p_decision': 'duplicate',
      'p_remarks': null,
    });
    await _repo.refresh();
  }

  @override
  Future<void> clearDuplicateFlag(Actor actor, String complaintId) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'review duplicates');
    final uuid = await _repo.requireUuid(complaintId);
    final pending = await _db.select('duplicate_candidates',
        eq: {'complaint_id': uuid, 'review_status': 'pending'});
    for (final p in pending) {
      await _db.rpc('review_duplicate', {
        'p_candidate_id': p['id'],
        'p_decision': 'not_duplicate',
        'p_remarks': null,
      });
    }
    await _repo.refresh();
  }

  /// Pending pairs from the database duplicate check. Score, distance and
  /// reason are the server's; wording overlap and category match are derived
  /// from the two reports' actual text for display.
  @override
  Future<Map<Complaint, List<DuplicateCandidate>>>
      duplicateReviewQueue() async {
    final rows = await _db.select('duplicate_candidates',
        eq: {'review_status': 'pending'}, orderBy: 'score');
    final all = await _repo.listComplaints();
    Complaint? byUuid(String uuid) =>
        all.where((c) => _repo.uuidOf(c.id) == uuid).firstOrNull;
    final result = <Complaint, List<DuplicateCandidate>>{};
    for (final r in rows) {
      final c = byUuid(r['complaint_id'] as String);
      final o = byUuid(r['candidate_id'] as String);
      if (c == null || o == null) continue;
      (result[c] ??= []).add(DuplicateCandidate(
        complaint: o,
        score: (DbCodec.toDouble(r['score']) ?? 0) / 100,
        textSimilarity: jaccardSimilarity(
            '${c.title} ${c.description}', '${o.title} ${o.description}'),
        sameCategory: c.category == o.category,
        distanceMeters: DbCodec.toDouble(r['distance_meters']),
        reasons: [if (r['reason'] != null) r['reason'] as String],
      ));
    }
    for (final list in result.values) {
      list.sort((a, b) => b.score.compareTo(a.score));
    }
    return result;
  }

  @override
  Future<void> updatePriorityRules(Actor actor, PriorityRules newRules) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'change priority rules');
    // save_priority_rule persists the rule; existing reports keep their
    // stored score until the server recalculates them.
    await _rulesRepo.save(newRules);
    await _repo.refresh();
  }

  /// Scores are calculated by the database, not re-computed on the client.
  @override
  Future<void> recomputePriorities() async {}

  @override
  Future<void> advanceForWork(
          Actor actor, String complaintId, ComplaintStatus to,
          {String? note, String? contractorId, String? jobId}) async =>
      throw const WorkflowException(
          'Work status changes are made by the repair workflow.');

  @override
  Future<void> linkJob(Actor actor, String complaintId, String jobId) async =>
      throw const WorkflowException('Jobs are linked by the server.');

  Future<Complaint> _require(String id) async {
    final c = await _repo.findById(id);
    if (c == null) throw WorkflowException('Report $id was not found.');
    return c;
  }
}
