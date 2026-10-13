import 'dart:typed_data';

import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/models/media_attachment.dart';
import 'package:civicconnect_ai/core/models/workflow_exception.dart';
import 'package:civicconnect_ai/core/supabase/db_errors.dart';
import 'package:civicconnect_ai/core/utils/geo.dart';
import 'package:civicconnect_ai/features/auth/domain/auth_repository.dart';
import 'package:civicconnect_ai/features/complaints/data/supabase_complaint_repository.dart';
import 'package:civicconnect_ai/features/complaints/data/supabase_complaint_service.dart';
import 'package:civicconnect_ai/features/complaints/data/supabase_priority_rules_repository.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/complaint_service.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/priority_engine.dart';
import 'package:civicconnect_ai/features/jobs/data/supabase_job_repositories.dart';
import 'package:civicconnect_ai/features/jobs/data/supabase_job_service.dart';
import 'package:civicconnect_ai/features/jobs/domain/contractor.dart';
import 'package:civicconnect_ai/features/notifications/data/supabase_notification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_backend.dart';

const me = 'user-citizen-1';
const muni = 'muni-1';
final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
final png =
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

const citizenActor = Actor(id: me, name: 'Sana', role: AppRole.citizen);
const adminActor =
    Actor(id: 'admin-1', name: 'Officer', role: AppRole.municipalAdmin);

class Backend {
  Backend({String? user = me, bool linkedMunicipality = true}) {
    db = FakeDb(currentUserId: user);
    media = FakeMediaStore();
    complaints = SupabaseComplaintRepository(db, media);
    jobs = SupabaseJobRepository(db, media);
    contractors = SupabaseContractorRepository(db);
    notifications = SupabaseNotificationRepository(db);
    rules = SupabasePriorityRulesRepository(db, municipalityId: () => muni);
    profile = linkedMunicipality ? citizenProfile() : null;
    service = SupabaseComplaintService(
      complaints: complaints,
      rules: rules,
      contractors: contractors,
      notifications: notifications,
      jobs: jobs,
      db: db,
      media: media,
      profile: () => profile,
    );
    jobService = SupabaseJobService(
      jobs: jobs,
      contractors: contractors,
      complaintRepository: complaints,
      complaints: service,
      notifications: notifications,
      db: db,
      media: media,
    );
  }

  late final FakeDb db;
  late final FakeMediaStore media;
  late final SupabaseComplaintRepository complaints;
  late final SupabaseJobRepository jobs;
  late final SupabaseContractorRepository contractors;
  late final SupabaseNotificationRepository notifications;
  late final SupabasePriorityRulesRepository rules;
  late UserProfile? profile;
  late final SupabaseComplaintService service;
  late final SupabaseJobService jobService;

  Future<String> seedComplaint(
      {String status = 'submitted', String citizen = 'someone-else'}) async {
    final row = await db.insert('complaints', {
      'citizen_id': citizen,
      'municipality_id': muni,
      'title': 'Streetlight broken on Station Road',
      'description': 'Three lamps are dark every night near the station.',
      'category': 'streetlight',
      'latitude': 24.8,
      'longitude': 67.0,
      'status': status,
    });
    db.calls.clear();
    return row['reference_code'] as String;
  }
}

ComplaintInput input(
        {List<MediaAttachment> photos = const [], GeoPoint? location}) =>
    ComplaintInput(
      title: 'Garbage overflowing at the park gate',
      description: 'Bins are full and garbage is spilling onto the road.',
      category: ComplaintCategory.garbage,
      address: 'Community Park gate',
      location: location ?? const GeoPoint(24.86, 67.0),
      locationSource: LocationSource.gps,
      photos: photos,
    );

MediaAttachment photo(Uint8List bytes) => MediaAttachment(
    id: 'p${bytes.hashCode}',
    storage: MediaStorage.localMemory,
    caption: 'photo',
    bytes: bytes);

void main() {
  group('citizen submission', () {
    test('creates the complaint first, then uploads to its uuid folder',
        () async {
      final b = Backend();
      final created = await b.service
          .submit(citizenActor, input(photos: [photo(jpeg), photo(png)]));

      expect(b.db.calls.indexOf('insert:complaints'),
          lessThan(b.db.calls.indexOf('insert:complaint_images')));
      final row = b.db.table('complaints').single;
      expect(row['citizen_id'], me);
      expect(row['municipality_id'], muni);
      expect(row['category'], 'garbage');
      expect(row.containsKey('status'), isTrue,
          reason: 'status/priority are set by the database, not the client');
      expect(created.id, row['reference_code'],
          reason: 'database-generated reference code is used');

      final uuid = row['id'] as String;
      expect(b.media.uploads.map((u) => u.$1).toSet(), {'complaint-images'});
      for (final u in b.media.uploads) {
        expect(u.$2,
            matches(RegExp('^complaints/$uuid/[0-9a-f-]+\\.(jpg|png)\$')));
      }
      expect(b.media.uploads.map((u) => u.$3), ['image/jpeg', 'image/png']);
      final images = b.db.table('complaint_images');
      expect(images.map((i) => i['storage_path']),
          b.media.uploads.map((u) => u.$2),
          reason: 'only paths are stored, never signed URLs');
      expect(images.every((i) => i['kind'] == 'report'), isTrue);
      expect(created.photos.first.remoteUrl, startsWith('https://signed'));
    });

    test('a failed upload is reported, never shown as complete', () async {
      final b = Backend()..media.failAt = {1};
      final error = await b.service
          .submit(citizenActor, input(photos: [photo(jpeg), photo(jpeg)]))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<PartialSubmitException>());
      final partial = error! as PartialSubmitException;
      expect(partial.message, contains('1 of 2 photos could not be uploaded'));
      expect(b.db.table('complaint_images'), hasLength(1));
      expect(partial.complaint.photos, hasLength(1));
    });

    test('unsupported image types are rejected before anything is created',
        () async {
      final b = Backend();
      await expectLater(
          b.service.submit(
              citizenActor,
              input(photos: [
                photo(Uint8List.fromList([1, 2, 3, 4]))
              ])),
          throwsA(isA<WorkflowException>()));
      expect(b.db.table('complaints'), isEmpty);
      expect(b.media.uploads, isEmpty);
    });

    test('photos over the 5 MB bucket limit are refused', () async {
      final b = Backend();
      final big = Uint8List(5 * 1024 * 1024 + 1)..setAll(0, [0xFF, 0xD8, 0xFF]);
      await expectLater(
          b.service.submit(citizenActor, input(photos: [photo(big)])),
          throwsA(predicate((e) => '$e'.contains('5 MB'))));
      expect(b.db.table('complaints'), isEmpty);
    });

    test('a location is required (no invented coordinates)', () async {
      final b = Backend();
      const noLocation = ComplaintInput(
          title: 'Garbage overflowing at the park gate',
          description: 'Bins are full and garbage is spilling onto the road.',
          category: ComplaintCategory.garbage,
          address: 'Community Park gate');
      await expectLater(b.service.submit(citizenActor, noLocation),
          throwsA(predicate((e) => '$e'.contains('Add the location'))));
      expect(b.db.table('complaints'), isEmpty);
    });

    test('accounts without a municipality use the only municipality', () async {
      final b = Backend(linkedMunicipality: false);
      b.db.table('municipalities').add({'id': 'only-muni', 'name': 'City'});
      await b.service.submit(citizenActor, input());
      expect(b.db.table('complaints').single['municipality_id'], 'only-muni');
    });

    test('with several municipalities and none linked, submission stops',
        () async {
      final b = Backend(linkedMunicipality: false);
      b.db.table('municipalities')
        ..add({'id': 'a', 'name': 'A'})
        ..add({'id': 'b', 'name': 'B'});
      await expectLater(b.service.submit(citizenActor, input()),
          throwsA(predicate((e) => '$e'.contains('not linked'))));
    });

    test('support toggles a row for the signed-in user', () async {
      final b = Backend();
      final ref = await b.seedComplaint();
      await b.service.toggleSupport(citizenActor, ref);
      expect(b.db.table('complaint_support').single['user_id'], me);
      await b.service.toggleSupport(citizenActor, ref);
      expect(b.db.table('complaint_support'), isEmpty);
    });

    test('comments are inserted as the signed-in user', () async {
      final b = Backend();
      final ref = await b.seedComplaint();
      await b.service.addComment(citizenActor, ref, ' Still dark tonight. ');
      final row = b.db.table('complaint_comments').single;
      expect(row['user_id'], me);
      expect(row['body'], 'Still dark tonight.');
      final c = await b.complaints.findById(ref);
      expect(c!.comments.single.text, 'Still dark tonight.');
    });

    test('drafts stay on the device and never reach the database', () async {
      final b = Backend();
      final draft = await b.service.saveDraft(citizenActor, input());
      expect(draft.id, startsWith('DRAFT-'));
      expect(b.db.table('complaints'), isEmpty);
      expect((await b.complaints.listComplaints()).first.id, draft.id);
      await b.service.submit(citizenActor, input(), draftId: draft.id);
      final all = await b.complaints.listComplaints();
      expect(all.where((c) => c.id == draft.id), isEmpty,
          reason: 'submitted draft is replaced by the server record');
    });
  });

  group('municipal workflow uses the secure functions', () {
    test('verify and reject call review_complaint with remarks', () async {
      final b = Backend();
      b.db.rpcHandlers['review_complaint'] = (_) => null;
      final ref = await b.seedComplaint();
      final uuid = await b.complaints.requireUuid(ref);
      await b.service.verify(adminActor, ref, department: 'Electrical');
      await b.service.reject(adminActor, ref, 'Duplicate of an older report');
      expect(b.db.rpcCalls.map((c) => c.$1),
          ['review_complaint', 'review_complaint']);
      expect(b.db.rpcCalls.first.$2, {
        'p_complaint_id': uuid,
        'p_new_status': 'verified',
        'p_remarks': 'Verified. Routed to Electrical.',
      });
      expect(b.db.rpcCalls.last.$2['p_new_status'], 'rejected');
      expect(b.db.calls.where((c) => c.startsWith('update:')), isEmpty,
          reason: 'no direct UPDATE for privileged changes');
    });

    test('server error messages reach the UI unchanged', () async {
      final b = Backend();
      b.db.rpcHandlers['review_complaint'] = (_) => throw translateDbError(
          const PostgrestException(
              message: 'Complaint is outside your municipality',
              code: 'P0001'));
      final ref = await b.seedComplaint();
      await expectLater(
          b.service.verify(adminActor, ref, department: 'X'),
          throwsA(predicate(
              (e) => '$e' == 'Complaint is outside your municipality')));
    });

    test('only pairs flagged by the server can be merged', () async {
      final b = Backend();
      b.db.rpcHandlers['review_duplicate'] = (_) => null;
      final dup = await b.seedComplaint();
      final original = await b.seedComplaint();
      await expectLater(b.service.markDuplicate(adminActor, dup, original),
          throwsA(predicate((e) => '$e'.contains('not flagged'))));
      b.db.table('duplicate_candidates').add({
        'id': 'cand-1',
        'complaint_id': await b.complaints.requireUuid(dup),
        'candidate_id': await b.complaints.requireUuid(original),
        'score': 82,
        'distance_meters': 40,
        'reason': 'Same category within 40 m',
        'review_status': 'pending',
      });
      final queue = await b.service.duplicateReviewQueue();
      expect(queue.values.single.single.score, closeTo(0.82, 1e-9));
      expect(queue.values.single.single.distanceMeters, 40);
      await b.service.markDuplicate(adminActor, dup, original);
      expect(b.db.rpcCalls.last.$2, {
        'p_candidate_id': 'cand-1',
        'p_decision': 'duplicate',
        'p_remarks': null
      });
    });

    test('assigning a contractor calls assign_repair_job', () async {
      final b = Backend();
      final ref = await b.seedComplaint(status: 'verified');
      b.db.table('contractors').add({
        'id': 'ctr-1',
        'business_name': 'Metro Works',
        'verification_status': 'approved',
        'created_at': '2026-01-01T00:00:00Z',
      });
      final uuid = await b.complaints.requireUuid(ref);
      b.db.rpcHandlers['assign_repair_job'] = (p) {
        b.db.table('jobs').add({
          'id': 'abcdef12-0000-4000-8000-000000000001',
          'complaint_id': uuid,
          'title': p['p_title'],
          'budget': p['p_budget'],
          'status': 'awarded',
          'created_at': '2026-10-02T00:00:00Z',
        });
        return 'contract-uuid';
      };
      final job = await b.jobService.assignDirectly(adminActor, ref,
          contractorId: 'ctr-1', amount: 40000);
      final call = b.db.rpcCalls.single.$2;
      expect(call['p_complaint_id'], uuid);
      expect(call['p_contractor_id'], 'ctr-1');
      expect(call['p_approved_amount'], 40000);
      expect((call['p_award_reason'] as String).length, greaterThan(5));
      expect(job.complaintId, ref);
    });

    test('suspending contractors is refused (no server support)', () async {
      final b = Backend();
      b.db.table('contractors').add({
        'id': 'ctr-1',
        'business_name': 'Metro Works',
        'verification_status': 'approved',
        'created_at': '2026-01-01T00:00:00Z',
      });
      await expectLater(
          b.jobService.setContractorStatus(
              adminActor, 'ctr-1', ContractorStatus.suspended),
          throwsA(predicate((e) => '$e'.contains('not available yet'))));
      expect(b.db.rpcCalls, isEmpty);
    });

    Backend withPendingApplication() {
      final b = Backend(user: 'admin-1');
      b.db.table('contractors').add({
        'id': 'ctr-muet',
        'owner_id': 'owner-muet',
        'business_name': 'muet',
        'verification_status': 'pending',
        'municipality_id': 'khairpur',
        'created_at': '2026-10-13T00:00:00Z',
      });
      return b;
    }

    test('approve calls verify_contractor and shows the server result',
        () async {
      final b = withPendingApplication();
      b.db.rpcHandlers['verify_contractor'] = (p) {
        // What the database function does on success.
        b.db.table('contractors').single['verification_status'] =
            p['p_decision'];
        return null;
      };
      await b.jobService.setContractorStatus(
          adminActor, 'ctr-muet', ContractorStatus.approved);
      final call = b.db.rpcCalls.single;
      expect(call.$1, 'verify_contractor');
      expect(call.$2, {
        'p_contractor_id': 'ctr-muet',
        'p_decision': 'approved',
        'p_remarks': null,
      });
      expect((await b.contractors.findById('ctr-muet'))!.status,
          ContractorStatus.approved,
          reason: 'the list is reloaded from the server after approval');
    });

    test('a refused approval surfaces the server message, never success',
        () async {
      final b = withPendingApplication();
      b.db.rpcHandlers['verify_contractor'] = (_) => throw translateDbError(
          const PostgrestException(
              message: 'Contractor belongs to another municipality',
              code: 'P0001'));
      await expectLater(
          b.jobService.setContractorStatus(
              adminActor, 'ctr-muet', ContractorStatus.approved),
          throwsA(predicate(
              (e) => '$e' == 'Contractor belongs to another municipality')));
      expect((await b.contractors.findById('ctr-muet'))!.status,
          ContractorStatus.pendingApproval);
    });
  });

  group('contractor workflow', () {
    const contractorActor =
        Actor(id: 'ctr-1', name: 'Metro Works', role: AppRole.contractor);

    Future<(Backend, String)> withContract(String contractStatus) async {
      final b = Backend(user: 'owner-1');
      final ref = await b.seedComplaint(status: 'in_progress');
      const jobUuid = 'abcdef12-0000-4000-8000-000000000001';
      b.db.table('jobs').add({
        'id': jobUuid,
        'complaint_id': await b.complaints.requireUuid(ref),
        'title': 'Fix lights',
        'budget': 1000,
        'status': 'awarded',
        'created_at': '2026-10-02T00:00:00Z',
      });
      b.db.table('contracts').add({
        'id': 'contract-1',
        'job_id': jobUuid,
        'contractor_id': 'ctr-1',
        'approved_amount': 900,
        'status': contractStatus,
      });
      return (b, 'JOB-ABCDEF12');
    }

    test('evidence uploads to the contract folder, then add_repair_evidence',
        () async {
      final (b, job) = await withContract('in_progress');
      b.db.rpcHandlers['add_repair_evidence'] = (_) => 'evidence-1';
      await b.jobService.addEvidence(
          contractorActor,
          job,
          MediaAttachment(
              id: 'x',
              storage: MediaStorage.localMemory,
              caption: 'After',
              bytes: jpeg,
              stage: EvidenceStage.after));
      final upload = b.media.uploads.single;
      expect(upload.$1, 'repair-evidence');
      expect(upload.$2, startsWith('contracts/contract-1/'));
      expect(b.db.rpcCalls.single.$2, {
        'p_contract_id': 'contract-1',
        'p_storage_path': upload.$2,
        'p_evidence_type': 'after',
        'p_notes': null,
      });
    });

    test('evidence before starting work is refused', () async {
      final (b, job) = await withContract('awarded');
      await expectLater(
          b.jobService.addEvidence(
              contractorActor,
              job,
              MediaAttachment(
                  id: 'x',
                  storage: MediaStorage.localMemory,
                  caption: 'Before',
                  bytes: jpeg,
                  stage: EvidenceStage.before)),
          throwsA(predicate((e) => '$e'.contains('Start work first'))));
      expect(b.media.uploads, isEmpty);
    });

    test('start and submit use start_repair / submit_repair', () async {
      final (b, job) = await withContract('awarded');
      b.db.rpcHandlers['start_repair'] = (_) => null;
      b.db.rpcHandlers['submit_repair'] = (_) => null;
      await b.jobService.startWork(contractorActor, job);
      await b.jobService.requestCompletion(contractorActor, job, 'Done');
      expect(b.db.rpcCalls.map((c) => (c.$1, c.$2['p_contract_id'])),
          [('start_repair', 'contract-1'), ('submit_repair', 'contract-1')]);
    });

    test('bidding stays blocked until the server function exists', () async {
      final (b, job) = await withContract('awarded');
      await expectLater(
          b.jobService
              .submitBid(contractorActor, job, amount: 500, days: 3, note: ''),
          throwsA(predicate((e) => '$e'.contains('database update'))));
      expect(b.db.table('bids'), isEmpty, reason: 'no bid is faked');
    });

    test('inspection uses inspect_repair', () async {
      final (b, job) = await withContract('submitted');
      b.db.rpcHandlers['inspect_repair'] = (_) => null;
      await b.jobService
          .inspect(adminActor, job, accept: false, note: 'Lamp 3 still off');
      expect(b.db.rpcCalls.single.$2, {
        'p_contract_id': 'contract-1',
        'p_result': 'rework_required',
        'p_remarks': 'Lamp 3 still off',
      });
      expect(b.jobService.inspectionReleasesPayment, isFalse);
    });
  });

  group('notifications and priority rules', () {
    test('mark all read falls back to a direct update of own rows', () async {
      final b = Backend();
      b.db.table('notifications')
        ..add({
          'id': 'n1',
          'user_id': me,
          'title': 'Update',
          'body': 'Verified',
          'read_at': null,
          'created_at': '2026-10-01T00:00:00Z',
        })
        ..add({
          'id': 'n2',
          'user_id': me,
          'title': 'Old',
          'body': 'Read earlier',
          'read_at': '2026-09-01T00:00:00Z',
          'created_at': '2026-09-01T00:00:00Z',
        });
      await b.notifications.markAllRead(me);
      expect(b.db.table('notifications').first['read_at'], isNotNull);
      expect(
          b.db.table('notifications').last['read_at'], '2026-09-01T00:00:00Z',
          reason: 'already-read timestamps are kept');
    });

    test('rules load per municipality and save via save_priority_rule',
        () async {
      final b = Backend();
      b.db.table('priority_rules').add({
        'municipality_id': muni,
        'category': 'pothole',
        'base_score': 40,
        'age_weight': 2,
        'support_weight': 4,
      });
      b.db.rpcHandlers['save_priority_rule'] = (_) => 'rule-id';
      await b.rules.refresh();
      final rules = b.rules.current;
      expect(rules.categoryBase[ComplaintCategory.roadDamage], 40);
      expect(rules.pointsPerSupporter, 4);
      expect(rules.pointsPerDayOpen, 2);

      await b.rules.save(rules.copyWith(categoryBase: {
        ...rules.categoryBase,
        ComplaintCategory.garbage: 33,
      }));
      final call = b.db.rpcCalls.single;
      expect(call.$1, 'save_priority_rule');
      expect(call.$2['p_category'], 'garbage');
      expect(call.$2['p_base_score'], 33);
    });

    test('settings without server storage are not silently dropped', () async {
      final b = Backend();
      final rules = b.rules.current;
      await expectLater(b.rules.save(rules.copyWith(mediumThreshold: 31)),
          throwsA(predicate((e) => '$e'.contains('cannot be saved yet'))));
      await expectLater(
          b.rules.save(rules
              .copyWith(severityKeywords: {...rules.severityKeywords, 'x': 5})),
          throwsA(isA<WorkflowException>()));
      expect(b.db.rpcCalls, isEmpty);
      expect(PriorityRules.defaults, isNotNull);
    });
  });

  group('error translation', () {
    test('database errors become readable messages', () {
      expect(
          '${translateDbError(const PostgrestException(message: 'x', code: '42501'))}',
          'You do not have permission to do that.');
      expect(
          '${translateDbError(const PostgrestException(message: 'new row violates row-level security policy', code: null))}',
          'You do not have permission to do that.');
      expect(
          '${translateDbError(const PostgrestException(message: 'complaints_category_check', code: '23514'))}',
          contains('category'));
      expect(
          '${translateDbError(const AuthException('Invalid login credentials'))}',
          'Incorrect email or password.');
      expect(
          '${translateDbError(Exception('SocketException: Failed host lookup'))}',
          contains('Network problem'));
    });
  });
}
