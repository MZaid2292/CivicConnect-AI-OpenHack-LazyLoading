import 'package:uuid/uuid.dart';

import '../../../core/models/app_role.dart';
import '../../../core/models/media_attachment.dart';
import '../../../core/models/permissions.dart';
import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_gateway.dart';
import '../../../core/supabase/media_store.dart';
import '../../complaints/data/supabase_complaint_repository.dart';
import '../domain/contractor.dart';
import '../domain/job_service.dart';
import '../domain/work_job.dart';
import 'supabase_job_repositories.dart';

/// Repair-contract use cases against Supabase. Every action is a database
/// function that re-checks role, ownership, municipality and state:
/// assign_repair_job, inspect_repair, verify_contractor, start_repair,
/// add_repair_evidence, submit_repair. Tendering and bidding use
/// open_tender / submit_bid / award_bid from the pending migration and fail
/// with a clear message until it is applied — no bid is ever faked.
class SupabaseJobService extends JobService {
  SupabaseJobService({
    required SupabaseJobRepository super.jobs,
    required SupabaseContractorRepository super.contractors,
    required SupabaseComplaintRepository complaintRepository,
    required super.complaints,
    required super.notifications,
    required DbGateway db,
    required MediaStore media,
  })  : _jobRepo = jobs,
        _contractorRepo = contractors,
        _complaintRepo = complaintRepository,
        _db = db,
        _media = media;

  final SupabaseJobRepository _jobRepo;
  final SupabaseContractorRepository _contractorRepo;
  final SupabaseComplaintRepository _complaintRepo;
  final DbGateway _db;
  final MediaStore _media;
  static const _uuid = Uuid();

  /// Accepting an inspection resolves the report; simulated payment is a
  /// separate finance step on the server.
  @override
  bool get inspectionReleasesPayment => false;

  @override
  bool get bidsAreMock => false;

  Future<void> _refreshAll() async {
    await Future.wait([
      _jobRepo.refresh(),
      _complaintRepo.refresh(),
      _contractorRepo.refresh(),
    ]);
  }

  // ---- Admin -------------------------------------------------------------------

  @override
  Future<WorkJob> openTender(Actor actor, String complaintId,
      {required String title, required int budget}) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'open tenders');
    final jobId = await _db.rpc('open_tender', {
      'p_complaint_id': await _complaintRepo.requireUuid(complaintId),
      'p_title': title.trim(),
      'p_budget': budget,
    });
    await _refreshAll();
    return _jobByUuid(jobId as String);
  }

  @override
  Future<WorkJob> assignDirectly(Actor actor, String complaintId,
      {required String contractorId,
      required int amount,
      String? title}) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'assign contractors');
    final complaint = await _complaintRepo.findById(complaintId);
    if (complaint == null) {
      throw const WorkflowException('Report not found.');
    }
    final contractor = await _contractorRepo.findById(contractorId);
    final jobTitle =
        (title ?? '').trim().length >= 5 ? title!.trim() : complaint.title;
    await _db.rpc('assign_repair_job', {
      'p_complaint_id': await _complaintRepo.requireUuid(complaintId),
      'p_contractor_id': contractorId,
      'p_title': jobTitle,
      'p_budget': amount,
      'p_approved_amount': amount,
      'p_award_reason':
          'Direct assignment to ${contractor?.name ?? 'contractor'} by the '
              'municipality',
      'p_deadline': null,
    });
    await _refreshAll();
    return (await _jobRepo.listJobs())
        .firstWhere((j) => j.complaintId == complaintId);
  }

  @override
  Future<void> awardBid(Actor actor, String jobId, String bidId) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'award bids');
    await _db.rpc('award_bid', {'p_bid_id': bidId});
    await _refreshAll();
  }

  @override
  Future<void> inspect(Actor actor, String jobId,
      {required bool accept, required String note}) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'inspect work');
    if (!accept && note.trim().length < 5) {
      throw const WorkflowException('Explain what needs rework.');
    }
    await _db.rpc('inspect_repair', {
      'p_contract_id': await _jobRepo.requireContractId(jobId),
      'p_result': accept ? 'accepted' : 'rework_required',
      'p_remarks': note.trim().isEmpty ? null : note.trim(),
    });
    await _refreshAll();
  }

  @override
  Future<void> setContractorStatus(
      Actor actor, String contractorId, ContractorStatus status) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'approve contractors');
    final current = await _contractorRepo.findById(contractorId);
    if (current == null) throw const WorkflowException('Contractor not found.');
    final decision = switch (status) {
      ContractorStatus.approved
          when current.status == ContractorStatus.pendingApproval =>
        'approved',
      ContractorStatus.rejected => 'rejected',
      _ => null,
    };
    if (decision == null) {
      throw const WorkflowException(
          'The server supports approving or rejecting pending applications '
          'only. Suspending and reinstating are not available yet.');
    }
    await _db.rpc('verify_contractor', {
      'p_contractor_id': contractorId,
      'p_decision': decision,
      'p_remarks': null,
    });
    await _refreshAll();
  }

  // ---- Contractor ------------------------------------------------------------------

  @override
  Future<void> submitBid(Actor actor, String jobId,
      {required int amount, required int days, required String note}) async {
    requireRole(actor, {AppRole.contractor}, 'submit bids');
    if (amount <= 0) throw const WorkflowException('Enter a realistic amount.');
    if (days < 1 || days > 90) {
      throw const WorkflowException('Duration must be 1–90 days.');
    }
    await _db.rpc('submit_bid', {
      'p_job_id': await _jobRepo.requireJobId(jobId),
      'p_amount': amount,
      'p_estimated_days': days,
      'p_proposal': note.trim().isEmpty ? null : note.trim(),
    });
    await _refreshAll();
  }

  @override
  Future<void> startWork(Actor actor, String jobId) async {
    requireRole(actor, {AppRole.contractor}, 'update job progress');
    await _db.rpc('start_repair',
        {'p_contract_id': await _jobRepo.requireContractId(jobId)});
    await _refreshAll();
  }

  /// Progress entries are stored as photo evidence; a note alone has no
  /// server record.
  @override
  Future<void> addProgress(Actor actor, String jobId, String note,
      {MediaAttachment? photo}) async {
    requireRole(actor, {AppRole.contractor}, 'update job progress');
    if (photo == null) {
      throw const WorkflowException(
          'Progress updates are saved with a photo on the server. Add a '
          'before or after photo instead.');
    }
    await _uploadEvidence(jobId, photo, 'progress', note: note);
  }

  @override
  Future<void> addEvidence(
      Actor actor, String jobId, MediaAttachment photo) async {
    requireRole(actor, {AppRole.contractor}, 'update job progress');
    await _uploadEvidence(
        jobId, photo, photo.stage == EvidenceStage.after ? 'after' : 'before');
  }

  Future<void> _uploadEvidence(String jobId, MediaAttachment photo, String type,
      {String? note}) async {
    final bytes = photo.bytes;
    if (bytes == null) throw const WorkflowException('No photo captured.');
    final (mime, ext) = PhotoRules.detect(bytes);
    final job = await _jobRepo.findById(jobId);
    if (job != null && job.status != JobStatus.inProgress) {
      throw const WorkflowException(
          'Start work first — evidence can be added while work is in '
          'progress.');
    }
    final contract = await _jobRepo.requireContractId(jobId);
    final path = 'contracts/$contract/${_uuid.v4()}.$ext';
    await _media.upload(repairEvidenceBucket, path, bytes, contentType: mime);
    await _db.rpc('add_repair_evidence', {
      'p_contract_id': contract,
      'p_storage_path': path,
      'p_evidence_type': type,
      'p_notes': note?.trim().isEmpty ?? true ? null : note!.trim(),
    });
    await _refreshAll();
  }

  @override
  Future<void> requestCompletion(Actor actor, String jobId, String note) async {
    requireRole(actor, {AppRole.contractor}, 'update job progress');
    await _db.rpc('submit_repair',
        {'p_contract_id': await _jobRepo.requireContractId(jobId)});
    await _refreshAll();
  }

  Future<WorkJob> _jobByUuid(String uuid) async {
    final jobs = await _jobRepo.listJobs();
    for (final j in jobs) {
      if (await _jobRepo.requireJobId(j.id) == uuid) return j;
    }
    throw const WorkflowException('The new job could not be loaded.');
  }
}
