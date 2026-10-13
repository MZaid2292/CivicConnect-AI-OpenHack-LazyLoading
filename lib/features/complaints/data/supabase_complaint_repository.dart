import '../../../core/models/app_role.dart';
import '../../../core/models/media_attachment.dart';
import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_codec.dart';
import '../../../core/supabase/db_gateway.dart';
import '../../../core/supabase/live_collection.dart';
import '../../../core/supabase/media_store.dart';
import '../../../core/utils/geo.dart';
import '../domain/complaint.dart';
import '../domain/complaint_repository.dart';
import '../domain/services/category_classifier.dart';
import '../domain/services/priority_engine.dart';

const complaintImagesBucket = 'complaint-images';

class ServerClassification extends ClassificationResult {
  ServerClassification(ComplaintCategory suggested, this.method)
      : super([
          CategorySuggestion(
              category: suggested,
              score: 0,
              confidence: 0,
              matchedTerms: const []),
        ]);
  final String method;

  @override
  String get explanation => 'Suggested by the server '
      '(${method.replaceAll('_', ' ')}): ${top!.category.label}.';
}

typedef Person = (String name, AppRole? role);

class ComplaintRows {
  const ComplaintRows({
    required this.complaints,
    this.images = const [],
    this.support = const [],
    this.comments = const [],
    this.updates = const [],
    this.jobs = const [],
    this.contracts = const [],
    this.reviews = const [],
    this.people = const {},
    this.signedUrls = const {},
  });
  final List<Row> complaints;
  final List<Row> images;
  final List<Row> support;
  final List<Row> comments;
  final List<Row> updates;
  final List<Row> jobs;
  final List<Row> contracts;
  final List<Row> reviews;
  final Map<String, Person> people;
  final Map<String, String> signedUrls;
}

class ComplaintAssembler {
  const ComplaintAssembler(
      {this.classifier = const KeywordCategoryClassifier()});
  final KeywordCategoryClassifier classifier;

  List<Complaint> build(ComplaintRows r) {
    final refById = {
      for (final c in r.complaints)
        c['id'] as String: c['reference_code'] as String
    };
    List<Row> by(List<Row> rows, String key, String id) => [
          for (final x in rows)
            if (x[key] == id) x
        ];

    final jobByComplaint = {
      for (final j in r.jobs) j['complaint_id'] as String: j
    };
    final contractByJob = {
      for (final ct in r.contracts) ct['job_id'] as String: ct
    };

    return [
      for (final row in r.complaints)
        _complaint(row, r, refById, by, jobByComplaint, contractByJob)
    ];
  }

  Complaint _complaint(
    Row row,
    ComplaintRows r,
    Map<String, String> refById,
    List<Row> Function(List<Row>, String, String) by,
    Map<String, Row> jobByComplaint,
    Map<String, Row> contractByJob,
  ) {
    final id = row['id'] as String;
    final citizenId = row['citizen_id'] as String;
    final title = row['title'] as String;
    final description = row['description'] as String;
    final category = DbCodec.categoryFrom(row['category'] as String?);
    final duplicateOf = row['duplicate_of'] as String?;
    final status = DbCodec.statusFrom(row['status'] as String?,
        linkedDuplicate: duplicateOf != null);
    final score = DbCodec.toInt(row['priority_score']);
    final job = jobByComplaint[id];
    final contract = job == null ? null : contractByJob[job['id']];

    final updates = by(r.updates, 'complaint_id', id)
      ..sort((a, b) => (a['created_at'] as String? ?? '')
          .compareTo(b['created_at'] as String? ?? ''));
    final timeline = [
      for (final u in updates) _event(u, citizenId, r.people, refById),
    ];
    final rejection = updates.reversed
        .where((u) => u['new_status'] == 'rejected')
        .map((u) => u['remarks'] as String?)
        .firstWhere((m) => m != null && m.trim().isNotEmpty,
            orElse: () => null);

    final review = r.reviews
        .where((v) => v['complaint_id'] == id && v['citizen_id'] == citizenId)
        .firstOrNull;

    final lat = DbCodec.toDouble(row['latitude']);
    final lng = DbCodec.toDouble(row['longitude']);
    final suggested = row['suggested_category'] as String?;

    return Complaint(
      id: row['reference_code'] as String,
      title: title,
      description: description,
      category: category,
      status: status,
      address:
          (row['approximate_address'] as String?)?.trim().isNotEmpty == true
              ? row['approximate_address'] as String
              : (lat == null
                  ? ''
                  : '${lat.toStringAsFixed(5)}, '
                      '${lng!.toStringAsFixed(5)}'),
      reporterId: citizenId,
      reporterName: r.people[citizenId]?.$1 ?? 'Resident',
      createdAt: DbCodec.time(row['created_at']),
      priority: PriorityAssessment(
        score: score,
        level: DbCodec.priorityFrom(row['priority'] as String?),
        factors: [PriorityFactor('Score from municipal priority rules', score)],
      ),
      location: lat == null || lng == null ? null : GeoPoint(lat, lng),
      locationSource:
          lat == null ? LocationSource.none : LocationSource.recorded,
      photos: [
        for (final img in by(r.images, 'complaint_id', id))
          MediaAttachment(
            id: img['id'] as String,
            storage: MediaStorage.remoteUpload,
            caption: 'Report photo',
            remoteUrl: r.signedUrls[img['storage_path']],
          ),
      ],
      supporterIds: {
        for (final s in by(r.support, 'complaint_id', id))
          s['user_id'] as String
      },
      comments: [
        for (final cm in by(r.comments, 'complaint_id', id)
          ..sort((a, b) => (a['created_at'] as String? ?? '')
              .compareTo(b['created_at'] as String? ?? '')))
          ComplaintComment(
            id: cm['id'] as String,
            authorName: r.people[cm['user_id']]?.$1 ??
                (cm['user_id'] == citizenId ? 'Reporter' : 'Community member'),
            authorRole: r.people[cm['user_id']]?.$2 ?? AppRole.citizen,
            text: cm['body'] as String,
            at: DbCodec.time(cm['created_at']),
          ),
      ],
      timeline: timeline,
      classification: _classification(title, description, suggested,
          row['classification_method'] as String?),
      department: category.department,
      contractorId: contract?['contractor_id'] as String?,
      jobId: job == null ? null : DbCodec.jobRef(job['id'] as String),
      feedback: review == null
          ? null
          : CitizenFeedback(
              rating: DbCodec.toInt(review['rating']),
              comment: review['feedback'] as String? ?? '',
              at: DbCodec.time(review['created_at'])),
      duplicateOfId: duplicateOf == null ? null : refById[duplicateOf],
      rejectionReason: rejection,
    );
  }

  TimelineEvent _event(Row u, String citizenId, Map<String, Person> people,
      Map<String, String> refById) {
    final oldStatus = u['old_status'] as String?;
    final newStatus = u['new_status'] as String?;
    var note = (u['remarks'] as String?)?.trim();
    final linked = oldStatus == newStatus &&
        (note?.startsWith('Linked to complaint') ?? false);
    if (note != null) {
      refById.forEach((uuid, ref) => note = note!.replaceAll(uuid, ref));
    }
    final status =
        linked ? ComplaintStatus.duplicate : DbCodec.statusFrom(newStatus);
    final by = u['changed_by'] as String?;
    final person = by == null ? null : people[by];
    final role = person?.$2 ?? DbCodec.roleForStatus(status);
    return TimelineEvent(
      status: status,
      at: DbCodec.time(u['created_at']),
      actorName: person?.$1 ??
          (by == null
              ? 'CivicConnect'
              : by == citizenId
                  ? 'Reporter'
                  : switch (role) {
                      AppRole.citizen => 'Citizen',
                      AppRole.contractor => 'Contractor',
                      AppRole.municipalAdmin => 'Municipal staff',
                    }),
      actorRole: role,
      note: note == null || note!.isEmpty ? null : note,
    );
  }

  ClassificationResult _classification(
      String title, String description, String? suggested, String? method) {
    if (suggested == null) return const ClassificationResult.empty();
    final server = DbCodec.categoryFrom(suggested);
    final local = classifier.classify(title, description);
    if (local.top?.category == server) return local;
    return ServerClassification(server, method ?? 'keyword rules');
  }
}

class SupabaseComplaintRepository implements ComplaintRepository {
  SupabaseComplaintRepository(this._db, this._media,
      {this.assembler = const ComplaintAssembler(), this.rowLimit = 1000}) {
    _live = LiveCollection(_load);
  }

  final DbGateway _db;
  final MediaStore _media;
  final ComplaintAssembler assembler;
  final int rowLimit;
  late final LiveCollection<Complaint> _live;
  final _drafts = <Complaint>[];
  final _uuidByRef = <String, String>{};
  bool _namesRpcAvailable = true;
  int _draftCounter = 1;

  String? uuidOf(String reference) => _uuidByRef[reference];

  Future<String> requireUuid(String reference) async {
    if (!_uuidByRef.containsKey(reference)) await _live.list();
    final id = _uuidByRef[reference];
    if (id == null) throw WorkflowException('Report $reference was not found.');
    return id;
  }

  Future<void> refresh() => _live.refresh();

  void clear() {
    _live.clear();
    _drafts.clear();
    _uuidByRef.clear();
  }

  @override
  Stream<List<Complaint>> watchAll() =>
      _live.watch().map((server) => [..._drafts, ...server]);

  @override
  Future<List<Complaint>> listComplaints() async =>
      [..._drafts, ...await _live.list()];

  @override
  Future<Complaint?> findById(String id) async {
    final draft = _drafts.where((d) => d.id == id).firstOrNull;
    if (draft != null) return draft;
    return (await _live.list()).where((c) => c.id == id).firstOrNull;
  }

  @override
  Future<String> nextId() async => 'DRAFT-${_draftCounter++}';

  @override
  Future<void> save(Complaint complaint) async {
    if (complaint.status != ComplaintStatus.draft) {
      throw const WorkflowException(
          'Report changes must go through the municipal workflow.');
    }
    _drafts
      ..removeWhere((d) => d.id == complaint.id)
      ..insert(0, complaint);
    if (_live.isLoaded) {
      _live.emitLocal(_live.snapshot);
    } else {
      await _live.refresh().catchError((Object _) {});
    }
  }

  @override
  Future<void> saveAll(Iterable<Complaint> complaints) async {
    for (final c in complaints) {
      if (c.status == ComplaintStatus.draft) await save(c);
    }
  }

  void removeDraft(String id) => _drafts.removeWhere((d) => d.id == id);

  Future<List<Complaint>> _load() async {
    final complaints =
        await _db.select('complaints', orderBy: 'created_at', limit: rowLimit);
    final results = await Future.wait([
      _db.select('complaint_images',
          columns: 'id, complaint_id, storage_path, kind, created_at',
          limit: rowLimit * 4),
      _db.select('complaint_support',
          columns: 'complaint_id, user_id', limit: rowLimit * 20),
      _db.select('complaint_comments',
          orderBy: 'created_at', ascending: true, limit: rowLimit * 10),
      _db.select('complaint_updates',
          orderBy: 'created_at', ascending: true, limit: rowLimit * 10),
      _db.select('jobs', columns: 'id, complaint_id, status', limit: rowLimit),
      _db.select('contracts',
          columns: 'id, job_id, contractor_id, status', limit: rowLimit),
      _db.select('reviews', limit: rowLimit),
    ]);
    final images = results[0];
    final updates = results[3];
    final comments = results[2];
    final people = await _people({
      for (final c in complaints) c['citizen_id'] as String,
      for (final u in updates)
        if (u['changed_by'] != null) u['changed_by'] as String,
      for (final c in comments) c['user_id'] as String,
    });
    final urls = await _media.signedUrls(complaintImagesBucket,
        [for (final i in images) i['storage_path'] as String]);

    _uuidByRef
      ..clear()
      ..addAll({
        for (final c in complaints)
          c['reference_code'] as String: c['id'] as String
      });
    return assembler.build(ComplaintRows(
      complaints: complaints,
      images: images,
      support: results[1],
      comments: comments,
      updates: updates,
      jobs: results[4],
      contracts: results[5],
      reviews: results[6],
      people: people,
      signedUrls: urls,
    ));
  }

  Future<Map<String, Person>> _people(Set<String> ids) async {
    final out = <String, Person>{};
    void add(Row p) => out[p['id'] as String] = (
          (p['display_name'] as String?) ?? 'Resident',
          DbCodec.roleFrom(p['role'] as String?),
        );
    if (ids.isEmpty) return out;
    if (_namesRpcAvailable) {
      try {
        final rows = await _db.rpc('get_display_names', {'p_ids': ids.toList()})
            as List<dynamic>;
        for (final r in rows) {
          add(Map<String, dynamic>.from(r as Map));
        }
        return out;
      } on WorkflowException {
        _namesRpcAvailable = false;
      }
    }
    for (final p in await _db.select('profiles',
        columns: 'id, display_name, role', limit: rowLimit * 5)) {
      if (ids.contains(p['id'])) add(p);
    }
    return out;
  }
}
