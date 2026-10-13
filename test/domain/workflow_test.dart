import 'package:civicconnect_ai/core/config/app_config.dart';
import 'package:civicconnect_ai/core/di/app_dependencies.dart';
import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/models/media_attachment.dart';
import 'package:civicconnect_ai/core/models/workflow_exception.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint_workflow.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/complaint_service.dart';
import 'package:civicconnect_ai/features/jobs/domain/contractor.dart';
import 'package:civicconnect_ai/features/jobs/domain/work_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';

void main() {
  late AppDependencies deps;
  const citizen = Actor.demoCitizen;
  const admin = Actor.demoAdmin;
  const contractor = Actor.demoContractor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    deps = AppDependencies(await SharedPreferences.getInstance(),
        config: const AppConfig.offline(),
        locationService: FakeLocationService(),
        mediaPicker: FakeMediaPicker());
  });

  test('state machine rejects illegal transitions and wrong roles', () {
    expect(
        ComplaintWorkflow.isValidTransition(
            ComplaintStatus.submitted, ComplaintStatus.resolved),
        isFalse);
    expect(
        () => ComplaintWorkflow.ensure(ComplaintStatus.submitted,
            ComplaintStatus.verified, AppRole.citizen),
        throwsA(isA<WorkflowException>()));
    expect(
        ComplaintWorkflow.canTransition(ComplaintStatus.submitted,
            ComplaintStatus.verified, AppRole.municipalAdmin),
        isTrue);
  });

  test('mock repository refuses illegal status jumps', () async {
    final c = (await deps.complaintRepository.findById('CMP-1007'))!;
    expect(
        () => deps.complaintRepository
            .save(c.copyWith(status: ComplaintStatus.resolved)),
        throwsA(isA<WorkflowException>()));
  });

  test('citizen cannot verify; contractor cannot award', () async {
    expect(
        () => deps.complaintService
            .verify(citizen, 'CMP-1007', department: 'Sanitation'),
        throwsA(isA<WorkflowException>()));
    expect(() => deps.jobService.awardBid(contractor, 'JOB-505', 'bid-505-1'),
        throwsA(isA<WorkflowException>()));
  });

  test('pending contractors cannot receive work', () async {
    await deps.complaintService
        .verify(admin, 'CMP-1007', department: 'Sanitation');
    expect(
        () => deps.jobService.assignDirectly(admin, 'CMP-1007',
            contractorId: 'ctr-urban', amount: 1000),
        throwsA(isA<WorkflowException>()));
  });

  test('full lifecycle: report → verify → assign → work → inspect → rate',
      () async {
    final created = await deps.complaintService.submit(
        citizen,
        const ComplaintInput(
          title: 'Streetlight broken near bakery',
          description:
              'The street light pole is dark every night since Monday.',
          category: ComplaintCategory.streetlight,
          address: 'Bakery corner, Block 2',
        ));
    expect(created.status, ComplaintStatus.submitted);
    expect(
        created.classification!.top!.category, ComplaintCategory.streetlight);
    final all = await deps.complaintRepository.listComplaints();
    expect(all.first.id, created.id, reason: 'new report appears first');

    await deps.complaintService
        .verify(admin, created.id, department: 'Electrical Services');
    final job = await deps.jobService.assignDirectly(admin, created.id,
        contractorId: contractor.id, amount: 15000);
    expect(job.paymentStatus, PaymentStatus.heldSimulated);

    await deps.jobService.startWork(contractor, job.id);
    expect(() => deps.jobService.requestCompletion(contractor, job.id, ''),
        throwsA(isA<WorkflowException>()),
        reason: 'after photo required');
    await deps.jobService.addProgress(contractor, job.id, 'Replaced fitting');
    await deps.jobService.addEvidence(
        contractor,
        job.id,
        const MediaAttachment(
            id: 'p1',
            storage: MediaStorage.localMemory,
            caption: 'Lit at night',
            stage: EvidenceStage.after));
    await deps.jobService.requestCompletion(contractor, job.id, 'Done');

    // Rework loop once.
    await deps.jobService
        .inspect(admin, job.id, accept: false, note: 'Second lamp still off');
    var c = (await deps.complaintRepository.findById(created.id))!;
    expect(c.status, ComplaintStatus.reworkRequired);
    await deps.jobService.startWork(contractor, job.id);
    await deps.jobService.requestCompletion(contractor, job.id, 'Both lit');
    await deps.jobService.inspect(admin, job.id, accept: true, note: '');

    c = (await deps.complaintRepository.findById(created.id))!;
    expect(c.status, ComplaintStatus.resolved);
    expect(c.timeline.map((e) => e.status), [
      ComplaintStatus.submitted,
      ComplaintStatus.verified,
      ComplaintStatus.assigned,
      ComplaintStatus.inProgress,
      ComplaintStatus.awaitingInspection,
      ComplaintStatus.reworkRequired,
      ComplaintStatus.inProgress,
      ComplaintStatus.awaitingInspection,
      ComplaintStatus.resolved,
    ]);
    final finishedJob = (await deps.jobRepository.findById(job.id))!;
    expect(finishedJob.status, JobStatus.completed);
    expect(finishedJob.paymentStatus, PaymentStatus.releasedSimulated);

    final before = (await deps.contractorRepository.findById(contractor.id))!;
    await deps.complaintService.rateResolution(citizen, c.id, 5, 'Great');
    final after = (await deps.contractorRepository.findById(contractor.id))!;
    expect(after.ratingCount, before.ratingCount + 1);
    expect(() => deps.complaintService.rateResolution(citizen, c.id, 4, ''),
        throwsA(isA<WorkflowException>()));
  });

  test('tender → bid → award flow', () async {
    await deps.jobService.submitBid(contractor, 'JOB-505',
        amount: 140000, days: 4, note: 'Can start tomorrow');
    final job = (await deps.jobRepository.findById('JOB-505'))!;
    final bid = job.bids.firstWhere((b) => b.contractorId == contractor.id);
    await deps.jobService.awardBid(admin, 'JOB-505', bid.id);
    final c = (await deps.complaintRepository.findById('CMP-1006'))!;
    expect(c.status, ComplaintStatus.assigned);
    expect(c.contractorId, contractor.id);
  });

  test('duplicate review flags the seeded Canal Road report and merges',
      () async {
    final queue = await deps.complaintService.duplicateReviewQueue();
    final flagged = queue.keys.map((c) => c.id);
    expect(flagged, contains('CMP-1008'));
    await deps.complaintService.markDuplicate(admin, 'CMP-1008', 'CMP-1005');
    final original = (await deps.complaintRepository.findById('CMP-1005'))!;
    expect(original.supporterIds, contains('cit-omar'));
  });

  test('priority rules update re-scores all complaints', () async {
    final rules = deps.complaintService.rules;
    await deps.complaintService.updatePriorityRules(
        admin, rules.copyWith(pointsPerSupporter: 0, maxSupportPoints: 0));
    final c = (await deps.complaintRepository.findById('CMP-1003'))!;
    expect(
        c.priority.factors.any((f) => f.label.contains('supporters')), isFalse);
  });

  test('contractor approval is admin-only', () async {
    expect(
        () => deps.jobService.setContractorStatus(
            contractor, 'ctr-urban', ContractorStatus.approved),
        throwsA(isA<WorkflowException>()));
    await deps.jobService
        .setContractorStatus(admin, 'ctr-urban', ContractorStatus.approved);
    expect((await deps.contractorRepository.findById('ctr-urban'))!.status,
        ContractorStatus.approved);
  });
}
