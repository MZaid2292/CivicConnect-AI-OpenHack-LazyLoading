import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/models/media_attachment.dart';
import 'package:civicconnect_ai/core/supabase/db_codec.dart';
import 'package:civicconnect_ai/features/complaints/data/supabase_complaint_repository.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint_workflow.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/priority_engine.dart';
import 'package:civicconnect_ai/features/complaints/presentation/widgets/status_timeline.dart';
import 'package:civicconnect_ai/features/jobs/data/supabase_job_repositories.dart';
import 'package:civicconnect_ai/features/jobs/domain/contractor.dart';
import 'package:civicconnect_ai/features/jobs/domain/work_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const c1 = '11111111-aaaa-4aaa-8aaa-111111111111';
const c2 = '22222222-bbbb-4bbb-8bbb-222222222222';
const citizen = 'citizen-uuid';
const admin = 'admin-uuid';
const job1 = 'abcdef12-0000-4000-8000-000000000001';
const contract1 = 'contract-1';
const contractor1 = 'contractor-1';

Map<String, dynamic> complaintRow(String id, String ref,
        {String status = 'submitted',
        String category = 'pothole',
        String? duplicateOf,
        String? suggested = 'pothole'}) =>
    {
      'id': id,
      'reference_code': ref,
      'citizen_id': citizen,
      'title': 'Big pothole near the school gate',
      'description': 'A deep pothole that damages cars every morning.',
      'category': category,
      'latitude': 24.86,
      'longitude': 67.0,
      'approximate_address': 'School road',
      'status': status,
      'priority': 'high',
      'priority_score': 64,
      'duplicate_of': duplicateOf,
      'created_at': '2026-10-01T08:00:00Z',
      'suggested_category': suggested,
      'classification_method': 'keyword_rules',
    };

void main() {
  group('DbCodec', () {
    test('categories round-trip (pothole ↔ road damage)', () {
      for (final c in ComplaintCategory.values) {
        expect(DbCodec.categoryFrom(DbCodec.category(c)), c);
      }
      expect(DbCodec.category(ComplaintCategory.roadDamage), 'pothole');
      expect(DbCodec.categoryFrom('unknown'), ComplaintCategory.other);
    });

    test('every database status maps to a stage', () {
      expect(DbCodec.statusFrom('under_review'), ComplaintStatus.underReview);
      expect(DbCodec.statusFrom('awaiting_inspection'),
          ComplaintStatus.awaitingInspection);
      expect(DbCodec.statusFrom('rework_required'),
          ComplaintStatus.reworkRequired);
      expect(DbCodec.statusFrom('reopened'), ComplaintStatus.submitted);
      expect(DbCodec.statusFrom('submitted', linkedDuplicate: true),
          ComplaintStatus.duplicate);
      for (final s in ComplaintStatus.values) {
        if (s == ComplaintStatus.draft || s == ComplaintStatus.duplicate) {
          continue;
        }
        expect(DbCodec.statusFrom(DbCodec.status(s)), s);
      }
    });

    test('roles come only from the database value', () {
      expect(DbCodec.roleFrom('citizen'), AppRole.citizen);
      expect(DbCodec.roleFrom('municipal_admin'), AppRole.municipalAdmin);
      expect(DbCodec.roleFrom('contractor'), AppRole.contractor);
      expect(DbCodec.roleFrom('inspector'), isNull);
      expect(DbCodec.roleFrom('finance'), isNull);
      expect(DbCodec.roleFrom(null), isNull);
    });

    test('job status combines job and contract state', () {
      expect(DbCodec.jobStatusFrom(job: 'open', contract: null),
          JobStatus.openForBids);
      expect(DbCodec.jobStatusFrom(job: 'awarded', contract: 'submitted'),
          JobStatus.completionSubmitted);
      expect(DbCodec.jobStatusFrom(job: 'awarded', contract: 'rework'),
          JobStatus.reworkRequested);
      expect(DbCodec.jobStatusFrom(job: 'awarded', contract: 'accepted'),
          JobStatus.completed);
      expect(DbCodec.jobStatusFrom(job: 'cancelled', contract: null),
          JobStatus.cancelled);
    });

    test('payments are labelled as simulations', () {
      expect(DbCodec.paymentFrom('authorized'), PaymentStatus.heldSimulated);
      expect(DbCodec.paymentFrom('simulated_paid'),
          PaymentStatus.releasedSimulated);
      expect(DbCodec.paymentFrom(null), PaymentStatus.notStarted);
      expect(PaymentStatus.heldSimulated.label, contains('simulation'));
      expect(PaymentStatus.releasedSimulated.label, contains('simulation'));
    });

    test('display ids are short and stable', () {
      expect(DbCodec.jobRef(job1), 'JOB-ABCDEF12');
      expect(DbCodec.contractorRef(job1), 'CTR-ABCDEF12');
    });
  });

  group('ComplaintAssembler', () {
    final rows = ComplaintRows(
      complaints: [
        complaintRow(c1, 'CMP-AAAA1111', status: 'rejected'),
        complaintRow(c2, 'CMP-BBBB2222', duplicateOf: c1, suggested: 'garbage'),
      ],
      images: [
        {
          'id': 'img1',
          'complaint_id': c1,
          'storage_path': 'complaints/$c1/a.jpg'
        },
      ],
      support: [
        {'complaint_id': c1, 'user_id': 'u2'},
        {'complaint_id': c1, 'user_id': 'u3'},
      ],
      comments: [
        {
          'id': 'cm1',
          'complaint_id': c1,
          'user_id': admin,
          'body': 'We are checking this.',
          'created_at': '2026-10-01T09:00:00Z',
        },
      ],
      updates: [
        {
          'id': 'u1',
          'complaint_id': c1,
          'changed_by': citizen,
          'old_status': null,
          'new_status': 'submitted',
          'remarks': null,
          'created_at': '2026-10-01T08:00:00Z',
        },
        {
          'id': 'u2',
          'complaint_id': c1,
          'changed_by': admin,
          'old_status': 'submitted',
          'new_status': 'rejected',
          'remarks': 'Private property, not municipal.',
          'created_at': '2026-10-01T10:00:00Z',
        },
        {
          'id': 'u3',
          'complaint_id': c2,
          'changed_by': admin,
          'old_status': 'submitted',
          'new_status': 'submitted',
          'remarks': 'Linked to complaint $c1',
          'created_at': '2026-10-02T10:00:00Z',
        },
      ],
      people: {admin: ('Ward Officer', AppRole.municipalAdmin)},
      signedUrls: {'complaints/$c1/a.jpg': 'https://signed/a.jpg'},
    );
    final built = const ComplaintAssembler().build(rows);
    final first = built.firstWhere((c) => c.id == 'CMP-AAAA1111');
    final second = built.firstWhere((c) => c.id == 'CMP-BBBB2222');

    test('uses the reference code and server fields', () {
      expect(first.category, ComplaintCategory.roadDamage);
      expect(first.status, ComplaintStatus.rejected);
      expect(first.priority.score, 64);
      expect(first.priority.level, PriorityLevel.high);
      expect(first.location!.latitude, 24.86);
      expect(first.locationSource, LocationSource.recorded);
    });

    test('photos are private uploads shown through signed URLs', () {
      expect(first.photos.single.storage, MediaStorage.remoteUpload);
      expect(first.photos.single.remoteUrl, 'https://signed/a.jpg');
    });

    test('support, comments and real history are attached', () {
      expect(first.supporterIds, {'u2', 'u3'});
      expect(first.comments.single.authorName, 'Ward Officer');
      expect(first.timeline.map((e) => e.status),
          [ComplaintStatus.submitted, ComplaintStatus.rejected]);
      expect(first.timeline.first.actorName, 'Reporter',
          reason: 'private names fall back to the workflow role');
      expect(first.rejectionReason, 'Private property, not municipal.');
    });

    test('duplicate links resolve to reference codes', () {
      expect(second.status, ComplaintStatus.duplicate);
      expect(second.duplicateOfId, 'CMP-AAAA1111');
      expect(second.timeline.single.status, ComplaintStatus.duplicate);
      expect(second.timeline.single.note, 'Linked to complaint CMP-AAAA1111');
    });

    test('server classification is reported without invented confidence', () {
      expect(first.classification!.top!.category, ComplaintCategory.roadDamage);
      expect(first.classification!.top!.matchedTerms, isNotEmpty,
          reason: 'app keywords agree with the server');
      final server = second.classification!;
      expect(server, isA<ServerClassification>());
      expect(server.top!.category, ComplaintCategory.garbage);
      expect(server.top!.confidence, 0);
      expect(server.explanation, contains('Suggested by the server'));
    });

    test('empty database yields no complaints', () {
      expect(
          const ComplaintAssembler().build(const ComplaintRows(complaints: [])),
          isEmpty);
    });
  });

  group('JobAssembler / ContractorAssembler', () {
    final jobs = const JobAssembler().build(JobRows(
      jobs: [
        {
          'id': job1,
          'complaint_id': c1,
          'title': 'Patch pothole',
          'budget': 50000,
          'status': 'awarded',
          'created_at': '2026-10-02T08:00:00Z',
        },
      ],
      contracts: [
        {
          'id': contract1,
          'job_id': job1,
          'contractor_id': contractor1,
          'approved_amount': 45000,
          'status': 'accepted',
        },
      ],
      contractors: [
        {'id': contractor1, 'business_name': 'Metro Works'},
      ],
      evidence: [
        {
          'id': 'e1',
          'contract_id': contract1,
          'evidence_type': 'before',
          'storage_path': 'contracts/$contract1/b.jpg',
          'created_at': '2026-10-03T08:00:00Z',
        },
        {
          'id': 'e2',
          'contract_id': contract1,
          'evidence_type': 'after',
          'storage_path': 'contracts/$contract1/a.jpg',
          'created_at': '2026-10-04T08:00:00Z',
        },
      ],
      inspections: [
        {
          'id': 'i1',
          'contract_id': contract1,
          'result': 'accepted',
          'remarks': null,
          'created_at': '2026-10-05T08:00:00Z',
        },
      ],
      payments: [
        {'id': 'p1', 'contract_id': contract1, 'status': 'authorized'},
      ],
      complaints: [
        {'id': c1, 'reference_code': 'CMP-AAAA1111', 'category': 'pothole'},
      ],
      signedUrls: {'contracts/$contract1/a.jpg': 'https://signed/a'},
    ));

    test('contract state, evidence, inspection and payment are mapped', () {
      final j = jobs.single;
      expect(j.id, 'JOB-ABCDEF12');
      expect(j.complaintId, 'CMP-AAAA1111');
      expect(j.status, JobStatus.completed);
      expect(j.contractorName, 'Metro Works');
      expect(j.awardedAmount, 45000);
      expect(j.beforePhotos, hasLength(1));
      expect(j.afterPhotos.single.remoteUrl, 'https://signed/a');
      expect(j.inspectionNote, 'Inspection passed.');
      expect(j.paymentStatus, PaymentStatus.heldSimulated);
      expect(j.completedAt, isNotNull);
    });

    test('contractor ratings and completed jobs come from real records', () {
      final list = const ContractorAssembler().build(
        contractors: [
          {
            'id': contractor1,
            'business_name': 'Metro Works',
            'verification_status': 'approved',
            'created_at': '2026-01-01T00:00:00Z',
          },
        ],
        contracts: [
          {'id': contract1, 'contractor_id': contractor1, 'status': 'accepted'},
        ],
        reviews: [
          {'contract_id': contract1, 'rating': 4},
          {'contract_id': contract1, 'rating': 5},
        ],
      );
      final c = list.single;
      expect(c.status, ContractorStatus.approved);
      expect(c.averageRating, 4.5);
      expect(c.completedJobs, 1);
      expect(c.registrationNo, startsWith('CTR-'));
    });
  });

  group('stage tracker', () {
    test('under review is a workflow stage handled by the municipality', () {
      expect(ComplaintStatus.underReview.label, 'Under review');
      expect(
          ComplaintWorkflow.canTransition(ComplaintStatus.submitted,
              ComplaintStatus.underReview, AppRole.municipalAdmin),
          isTrue);
      expect(
          ComplaintWorkflow.canTransition(ComplaintStatus.underReview,
              ComplaintStatus.verified, AppRole.citizen),
          isFalse);
    });

    testWidgets('under review sits on the first step without a new step',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 360,
                  child: StatusTracker(status: ComplaintStatus.underReview)))));
      expect(find.text('Under review'), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsOneWidget,
          reason: 'tracker keeps its six approved steps');
    });
  });
}
