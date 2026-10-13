import '../../../core/models/media_attachment.dart';
import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_codec.dart';
import '../../../core/supabase/db_gateway.dart';
import '../../../core/supabase/live_collection.dart';
import '../../../core/supabase/media_store.dart';
import '../../complaints/domain/complaint.dart';
import '../domain/contractor.dart';
import '../domain/job_repositories.dart';
import '../domain/work_job.dart';

const repairEvidenceBucket = 'repair-evidence';

class JobRows {
  const JobRows({
    required this.jobs,
    this.contracts = const [],
    this.bids = const [],
    this.contractors = const [],
    this.evidence = const [],
    this.inspections = const [],
    this.payments = const [],
    this.complaints = const [],
    this.signedUrls = const {},
  });
  final List<Row> jobs;
  final List<Row> contracts;
  final List<Row> bids;
  final List<Row> contractors;
  final List<Row> evidence;
  final List<Row> inspections;
  final List<Row> payments;
  final List<Row> complaints;
  final Map<String, String> signedUrls;
}

class JobAssembler {
  const JobAssembler();

  List<WorkJob> build(JobRows r) {
    final complaintById = {for (final c in r.complaints) c['id'] as String: c};
    final contractorName = {
      for (final c in r.contractors)
        c['id'] as String: c['business_name'] as String
    };
    final contractByJob = {
      for (final ct in r.contracts) ct['job_id'] as String: ct
    };
    final out = <WorkJob>[];
    for (final j in r.jobs) {
      final complaint = complaintById[j['complaint_id']];
      if (complaint == null) continue;
      final contract = contractByJob[j['id']];
      final contractId = contract?['id'] as String?;
      final evidence = contractId == null
          ? const <Row>[]
          : ([
              for (final e in r.evidence)
                if (e['contract_id'] == contractId) e
            ]..sort((a, b) => (a['created_at'] as String? ?? '')
              .compareTo(b['created_at'] as String? ?? '')));
      final inspections = contractId == null
          ? const <Row>[]
          : ([
              for (final i in r.inspections)
                if (i['contract_id'] == contractId) i
            ]..sort((a, b) => (a['created_at'] as String? ?? '')
              .compareTo(b['created_at'] as String? ?? '')));
      final lastInspection = inspections.lastOrNull;
      final payment = contractId == null
          ? null
          : r.payments.where((p) => p['contract_id'] == contractId).firstOrNull;
      final contractorId = contract?['contractor_id'] as String?;
      final category = DbCodec.categoryFrom(complaint['category'] as String?);

      MediaAttachment photo(Row e, String caption) => MediaAttachment(
            id: e['id'] as String,
            storage: MediaStorage.remoteUpload,
            caption: caption,
            remoteUrl: r.signedUrls[e['storage_path']],
            stage: switch (e['evidence_type']) {
              'before' => EvidenceStage.before,
              'after' => EvidenceStage.after,
              _ => EvidenceStage.progress,
            },
          );

      out.add(WorkJob(
        id: DbCodec.jobRef(j['id'] as String),
        complaintId: complaint['reference_code'] as String,
        title: j['title'] as String,
        category: category,
        department: category.department,
        budgetEstimate:
            DbCodec.toInt(j['budget'] ?? contract?['approved_amount']),
        status: DbCodec.jobStatusFrom(
            job: j['status'] as String?,
            contract: contract?['status'] as String?),
        createdAt: DbCodec.time(j['created_at']),
        bids: [
          for (final b in r.bids)
            if (b['job_id'] == j['id'])
              Bid(
                id: b['id'] as String,
                contractorId: b['contractor_id'] as String,
                contractorName:
                    contractorName[b['contractor_id']] ?? 'Contractor',
                amount: DbCodec.toInt(b['amount']),
                days: DbCodec.toInt(b['estimated_days']),
                note: b['proposal'] as String? ?? '',
                at: DbCodec.time(b['created_at']),
              ),
        ],
        contractorId: contractorId,
        contractorName:
            contractorId == null ? null : contractorName[contractorId],
        awardedAmount: contract == null
            ? null
            : DbCodec.toInt(contract['approved_amount']),
        progressLogs: [
          for (final e in evidence)
            if (e['evidence_type'] == 'progress')
              ProgressLog(
                id: e['id'] as String,
                note: e['notes'] as String? ?? 'Progress photo',
                at: DbCodec.time(e['created_at']),
                authorName: contractorId == null
                    ? 'Contractor'
                    : contractorName[contractorId] ?? 'Contractor',
                photo: photo(e, 'Progress'),
              ),
        ],
        beforePhotos: [
          for (final e in evidence)
            if (e['evidence_type'] == 'before') photo(e, 'Before'),
        ],
        afterPhotos: [
          for (final e in evidence)
            if (e['evidence_type'] == 'after') photo(e, 'After'),
        ],
        inspectionNote: lastInspection == null
            ? null
            : ((lastInspection['remarks'] as String?)?.trim().isNotEmpty == true
                ? lastInspection['remarks'] as String
                : (lastInspection['result'] == 'accepted'
                    ? 'Inspection passed.'
                    : 'Rework required.')),
        paymentStatus: DbCodec.paymentFrom(payment?['status'] as String?),
        completedAt: lastInspection?['result'] == 'accepted'
            ? DbCodec.time(lastInspection!['created_at'])
            : null,
      ));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }
}

class SupabaseJobRepository implements JobRepository {
  SupabaseJobRepository(this._db, this._media,
      {this.assembler = const JobAssembler(), this.rowLimit = 1000}) {
    _live = LiveCollection(_load);
  }

  final DbGateway _db;
  final MediaStore _media;
  final JobAssembler assembler;
  final int rowLimit;
  late final LiveCollection<WorkJob> _live;
  final _jobUuidByRef = <String, String>{};
  final _contractUuidByRef = <String, String>{};

  Future<void> refresh() => _live.refresh();

  void clear() {
    _live.clear();
    _jobUuidByRef.clear();
    _contractUuidByRef.clear();
  }

  Future<String> requireContractId(String jobRef) async {
    if (!_contractUuidByRef.containsKey(jobRef)) await _live.refresh();
    final id = _contractUuidByRef[jobRef];
    if (id == null) {
      throw WorkflowException('$jobRef has no contract yet.');
    }
    return id;
  }

  Future<String> requireJobId(String jobRef) async {
    if (!_jobUuidByRef.containsKey(jobRef)) await _live.list();
    final id = _jobUuidByRef[jobRef];
    if (id == null) throw WorkflowException('Job $jobRef was not found.');
    return id;
  }

  @override
  Stream<List<WorkJob>> watchAll() => _live.watch();

  @override
  Future<List<WorkJob>> listJobs() => _live.list();

  @override
  Future<WorkJob?> findById(String id) async =>
      (await _live.list()).where((j) => j.id == id).firstOrNull;

  @override
  Future<String> nextId() async =>
      throw const WorkflowException('Jobs are created by the server.');

  @override
  Future<void> save(WorkJob job) async => throw const WorkflowException(
      'Job changes must go through the municipal workflow.');

  Future<List<WorkJob>> _load() async {
    final r = await Future.wait([
      _db.select('jobs', orderBy: 'created_at', limit: rowLimit),
      _db.select('contracts', limit: rowLimit),
      _db.select('bids', limit: rowLimit * 5),
      _db.select('contractors', columns: 'id, business_name', limit: rowLimit),
      _db.select('work_evidence', limit: rowLimit * 10),
      _db.select('inspections', limit: rowLimit * 2),
      _db.select('payments', limit: rowLimit),
      _db.select('complaints',
          columns: 'id, reference_code, category', limit: rowLimit * 5),
    ]);
    final jobs = r[0], contracts = r[1], evidence = r[4];
    final urls = await _media.signedUrls(repairEvidenceBucket,
        [for (final e in evidence) e['storage_path'] as String]);
    final contractByJob = {
      for (final ct in contracts) ct['job_id'] as String: ct['id'] as String
    };
    _jobUuidByRef.clear();
    _contractUuidByRef.clear();
    for (final j in jobs) {
      final ref = DbCodec.jobRef(j['id'] as String);
      _jobUuidByRef[ref] = j['id'] as String;
      final contract = contractByJob[j['id']];
      if (contract != null) _contractUuidByRef[ref] = contract;
    }
    return assembler.build(JobRows(
      jobs: jobs,
      contracts: contracts,
      bids: r[2],
      contractors: r[3],
      evidence: evidence,
      inspections: r[5],
      payments: r[6],
      complaints: r[7],
      signedUrls: urls,
    ));
  }
}

class ContractorAssembler {
  const ContractorAssembler();

  List<Contractor> build(
      {required List<Row> contractors,
      List<Row> contracts = const [],
      List<Row> reviews = const []}) {
    final contractorByContract = {
      for (final ct in contracts)
        ct['id'] as String: ct['contractor_id'] as String
    };
    return [
      for (final c in contractors)
        () {
          final id = c['id'] as String;
          final ratings = [
            for (final v in reviews)
              if (contractorByContract[v['contract_id']] == id)
                DbCodec.toInt(v['rating'])
          ];
          return Contractor(
            id: id,
            name: c['business_name'] as String,
            registrationNo: DbCodec.contractorRef(id),
            specialties: const <ComplaintCategory>{},
            status: DbCodec.contractorStatusFrom(
                c['verification_status'] as String?),
            joinedAt: DbCodec.time(c['created_at']),
            ratingTotal: ratings.fold(0, (a, b) => a + b),
            ratingCount: ratings.length,
            completedJobs: contracts
                .where((ct) =>
                    ct['contractor_id'] == id && ct['status'] == 'accepted')
                .length,
          );
        }(),
    ];
  }
}

class SupabaseContractorRepository implements ContractorRepository {
  SupabaseContractorRepository(this._db,
      {this.assembler = const ContractorAssembler()}) {
    _live = LiveCollection(_load);
  }

  final DbGateway _db;
  final ContractorAssembler assembler;
  late final LiveCollection<Contractor> _live;

  Future<void> refresh() => _live.refresh();
  void clear() => _live.clear();

  @override
  Stream<List<Contractor>> watchAll() => _live.watch();

  @override
  Future<List<Contractor>> listContractors() => _live.list();

  @override
  Future<Contractor?> findById(String id) async =>
      (await _live.list()).where((c) => c.id == id).firstOrNull;

  @override
  Future<void> save(Contractor contractor) async =>
      throw const WorkflowException(
          'Contractor changes must go through municipal verification.');

  Future<List<Contractor>> _load() async {
    final r = await Future.wait([
      _db.select('contractors', orderBy: 'created_at'),
      _db.select('contracts', columns: 'id, contractor_id, status'),
      _db.select('reviews', columns: 'contract_id, rating'),
    ]);
    return assembler.build(contractors: r[0], contracts: r[1], reviews: r[2]);
  }
}
