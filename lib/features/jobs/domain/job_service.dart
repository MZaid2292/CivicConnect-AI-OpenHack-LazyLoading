import 'package:uuid/uuid.dart';

import '../../../core/models/app_role.dart';
import '../../../core/models/media_attachment.dart';
import '../../../core/models/permissions.dart';
import '../../../core/models/workflow_exception.dart';
import '../../complaints/domain/complaint.dart';
import '../../complaints/domain/services/complaint_service.dart';
import '../../notifications/domain/app_notification.dart';
import 'contractor.dart';
import 'job_repositories.dart';
import 'job_workflow.dart';
import 'work_job.dart';

/// Contract / work-order use cases. Keeps the job state machine and the
/// complaint state machine in step, and checks the actor's role and
/// ownership for every action.
class JobService {
  JobService({
    required JobRepository jobs,
    required ContractorRepository contractors,
    required ComplaintService complaints,
    required NotificationRepository notifications,
    DateTime Function()? clock,
  })  : _jobs = jobs,
        _contractors = contractors,
        _complaints = complaints,
        _notifications = notifications,
        _clock = clock ?? DateTime.now;

  final JobRepository _jobs;
  final ContractorRepository _contractors;
  final ComplaintService _complaints;
  final NotificationRepository _notifications;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  DateTime get _now => _clock();

  // ---- Admin ---------------------------------------------------------------

  Future<WorkJob> openTender(Actor actor, String complaintId,
      {required String title, required int budget}) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'open tenders');
    final complaint = await _verifiedWithoutJob(complaintId);
    _validateAmount(budget);
    final job = WorkJob(
      id: await _jobs.nextId(),
      complaintId: complaint.id,
      title: title.trim().isEmpty ? complaint.title : title.trim(),
      category: complaint.category,
      department: complaint.department ?? complaint.category.department,
      budgetEstimate: budget,
      status: JobStatus.openForBids,
      createdAt: _now,
    );
    await _jobs.save(job);
    await _complaints.linkJob(actor, complaint.id, job.id);
    return job;
  }

  Future<WorkJob> assignDirectly(Actor actor, String complaintId,
      {required String contractorId,
      required int amount,
      String? title}) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'assign contractors');
    final complaint = await _verifiedWithoutJob(complaintId);
    final contractor = await _approvedContractor(contractorId);
    _validateAmount(amount);
    final job = WorkJob(
      id: await _jobs.nextId(),
      complaintId: complaint.id,
      title: (title ?? '').trim().isEmpty ? complaint.title : title!.trim(),
      category: complaint.category,
      department: complaint.department ?? complaint.category.department,
      budgetEstimate: amount,
      status: JobStatus.awarded,
      createdAt: _now,
      contractorId: contractor.id,
      contractorName: contractor.name,
      awardedAmount: amount,
      paymentStatus: PaymentStatus.heldSimulated,
    );
    await _jobs.save(job);
    await _complaints.advanceForWork(
        actor, complaint.id, ComplaintStatus.assigned,
        note: 'Directly assigned to ${contractor.name}.',
        contractorId: contractor.id,
        jobId: job.id);
    await _notifyContractor(job, '${job.id} assigned to you', job.title);
    return job;
  }

  Future<void> awardBid(Actor actor, String jobId, String bidId) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'award bids');
    final job = await _require(jobId);
    final bid = job.bids.where((b) => b.id == bidId).firstOrNull;
    if (bid == null) throw const WorkflowException('Bid not found.');
    final contractor = await _approvedContractor(bid.contractorId);
    JobWorkflow.ensure(job.status, JobStatus.awarded, actor.role);
    final awarded = job.copyWith(
      status: JobStatus.awarded,
      contractorId: contractor.id,
      contractorName: contractor.name,
      awardedAmount: bid.amount,
      paymentStatus: PaymentStatus.heldSimulated,
    );
    await _complaints.advanceForWork(
        actor, job.complaintId, ComplaintStatus.assigned,
        note: 'Awarded to ${contractor.name} '
            '(${job.bids.length} bid${job.bids.length == 1 ? '' : 's'}).',
        contractorId: contractor.id,
        jobId: job.id);
    await _jobs.save(awarded);
    await _notifyContractor(awarded, '${job.id} awarded to you', job.title);
  }

  Future<void> inspect(Actor actor, String jobId,
      {required bool accept, required String note}) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'inspect work');
    final job = await _require(jobId);
    if (!accept && note.trim().length < 5) {
      throw const WorkflowException('Explain what needs rework.');
    }
    final next = accept ? JobStatus.completed : JobStatus.reworkRequested;
    JobWorkflow.ensure(job.status, next, actor.role);
    final noteText = note.trim().isEmpty
        ? (accept ? 'Inspection passed.' : 'Rework required.')
        : note.trim();
    await _complaints.advanceForWork(actor, job.complaintId,
        accept ? ComplaintStatus.resolved : ComplaintStatus.reworkRequired,
        note: noteText);
    await _jobs.save(job.copyWith(
      status: next,
      inspectionNote: noteText,
      paymentStatus: accept ? PaymentStatus.releasedSimulated : null,
      completedAt: accept ? _now : null,
    ));
    if (accept && job.contractorId != null) {
      final c = await _contractors.findById(job.contractorId!);
      if (c != null) {
        await _contractors.save(c.copyWith(completedJobs: c.completedJobs + 1));
      }
    }
    await _notifyContractor(job,
        accept ? '${job.id} accepted' : '${job.id} needs rework', noteText);
  }

  Future<void> setContractorStatus(
      Actor actor, String contractorId, ContractorStatus status) async {
    requireRole(actor, {AppRole.municipalAdmin}, 'approve contractors');
    final c = await _contractors.findById(contractorId);
    if (c == null) throw const WorkflowException('Contractor not found.');
    await _contractors.save(c.copyWith(status: status));
  }

  // ---- Contractor ------------------------------------------------------------

  Future<void> submitBid(Actor actor, String jobId,
      {required int amount, required int days, required String note}) async {
    requireRole(actor, {AppRole.contractor}, 'submit bids');
    await _approvedContractor(actor.id);
    final job = await _require(jobId);
    if (job.status != JobStatus.openForBids) {
      throw const WorkflowException('This job is no longer accepting bids.');
    }
    if (job.hasBidFrom(actor.id)) {
      throw const WorkflowException('You already bid on this job.');
    }
    _validateAmount(amount);
    if (days < 1 || days > 90) {
      throw const WorkflowException('Duration must be 1–90 days.');
    }
    await _jobs.save(job.copyWith(bids: [
      ...job.bids,
      Bid(
          id: _uuid.v4(),
          contractorId: actor.id,
          contractorName: actor.name,
          amount: amount,
          days: days,
          note: note.trim(),
          at: _now),
    ]));
  }

  Future<void> startWork(Actor actor, String jobId) async {
    final job = await _ownJob(actor, jobId);
    JobWorkflow.ensure(job.status, JobStatus.inProgress, actor.role);
    final resuming = job.status == JobStatus.reworkRequested;
    await _complaints.advanceForWork(
        actor, job.complaintId, ComplaintStatus.inProgress,
        note: resuming ? 'Rework started.' : 'Work started on site.');
    await _jobs.save(job.copyWith(status: JobStatus.inProgress));
  }

  Future<void> addProgress(Actor actor, String jobId, String note,
      {MediaAttachment? photo}) async {
    final job = await _ownJob(actor, jobId);
    if (job.status != JobStatus.inProgress) {
      throw const WorkflowException('Start work before logging progress.');
    }
    if (note.trim().length < 3) {
      throw const WorkflowException('Describe the progress made.');
    }
    await _jobs.save(job.copyWith(progressLogs: [
      ...job.progressLogs,
      ProgressLog(
          id: _uuid.v4(),
          note: note.trim(),
          at: _now,
          authorName: actor.name,
          photo: photo),
    ]));
  }

  Future<void> addEvidence(
      Actor actor, String jobId, MediaAttachment photo) async {
    final job = await _ownJob(actor, jobId);
    if (!{JobStatus.awarded, JobStatus.inProgress, JobStatus.reworkRequested}
        .contains(job.status)) {
      throw const WorkflowException('Evidence can no longer be changed.');
    }
    switch (photo.stage) {
      case EvidenceStage.after:
        await _jobs
            .save(job.copyWith(afterPhotos: [...job.afterPhotos, photo]));
      default:
        await _jobs
            .save(job.copyWith(beforePhotos: [...job.beforePhotos, photo]));
    }
  }

  Future<void> requestCompletion(Actor actor, String jobId, String note) async {
    final job = await _ownJob(actor, jobId);
    JobWorkflow.ensure(job.status, JobStatus.completionSubmitted, actor.role);
    if (job.afterPhotos.isEmpty) {
      throw const WorkflowException(
          'Add at least one "after" photo before requesting inspection.');
    }
    await _complaints.advanceForWork(
        actor, job.complaintId, ComplaintStatus.awaitingInspection,
        note: note.trim().isEmpty
            ? 'Work completed; ready for inspection.'
            : note.trim());
    await _jobs.save(job.copyWith(status: JobStatus.completionSubmitted));
  }

  // ---- Helpers ---------------------------------------------------------------

  void _validateAmount(int amount) {
    if (amount <= 0 || amount > 50000000) {
      throw const WorkflowException('Enter a realistic amount.');
    }
  }

  Future<WorkJob> _require(String id) async {
    final job = await _jobs.findById(id);
    if (job == null) throw WorkflowException('Job $id was not found.');
    return job;
  }

  Future<WorkJob> _ownJob(Actor actor, String id) async {
    requireRole(actor, {AppRole.contractor}, 'update job progress');
    final job = await _require(id);
    if (job.contractorId != actor.id) {
      throw const WorkflowException('This job is assigned to someone else.');
    }
    return job;
  }

  Future<Contractor> _approvedContractor(String id) async {
    final c = await _contractors.findById(id);
    if (c == null) throw const WorkflowException('Contractor not found.');
    if (!c.canReceiveWork) {
      throw WorkflowException('${c.name} is ${c.status.label.toLowerCase()}.');
    }
    return c;
  }

  Future<Complaint> _verifiedWithoutJob(String complaintId) async {
    final c = await _complaints.findById(complaintId);
    if (c == null) throw const WorkflowException('Report not found.');
    if (c.status != ComplaintStatus.verified) {
      throw const WorkflowException('Verify the report before creating work.');
    }
    if (c.jobId != null) {
      final existing = await _jobs.findById(c.jobId!);
      if (existing != null && existing.status != JobStatus.cancelled) {
        throw WorkflowException(
            '${existing.id} already exists for this report.');
      }
    }
    return c;
  }

  Future<void> _notifyContractor(WorkJob job, String title, String body) async {
    if (job.contractorId == null) return;
    await _notifications.add(AppNotification(
      id: _uuid.v4(),
      recipientId: job.contractorId!,
      title: title,
      body: body,
      at: _now,
      jobId: job.id,
    ));
  }
}
