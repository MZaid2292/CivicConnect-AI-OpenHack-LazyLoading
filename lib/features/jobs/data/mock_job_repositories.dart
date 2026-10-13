import '../../../core/data/in_memory_collection.dart';
import '../../../core/models/workflow_exception.dart';
import '../domain/contractor.dart';
import '../domain/job_repositories.dart';
import '../domain/job_workflow.dart';
import '../domain/work_job.dart';

class MockJobRepository implements JobRepository {
  MockJobRepository([Iterable<WorkJob> seed = const []])
      : _store = InMemoryCollection(seed, (j) => j.id),
        _counter = 500 + seed.length + 1;

  final InMemoryCollection<WorkJob> _store;
  int _counter;

  @override
  Stream<List<WorkJob>> watchAll() => _store.watch();

  @override
  Future<List<WorkJob>> listJobs() async => _store.snapshot;

  @override
  Future<WorkJob?> findById(String id) async => _store.find(id);

  @override
  Future<String> nextId() async {
    while (_store.find('JOB-$_counter') != null) {
      _counter++;
    }
    return 'JOB-${_counter++}';
  }

  @override
  Future<void> save(WorkJob job) async {
    final existing = _store.find(job.id);
    if (existing == null) {
      if (job.status != JobStatus.openForBids &&
          job.status != JobStatus.awarded) {
        throw const WorkflowException(
            'New jobs must start Open for bids or Awarded.');
      }
    } else if (existing.status != job.status &&
        !JobWorkflow.isValidTransition(existing.status, job.status)) {
      throw WorkflowException(
          'Illegal job transition ${existing.status.label} → ${job.status.label}.');
    }
    _store.upsert(job);
  }
}

class MockContractorRepository implements ContractorRepository {
  MockContractorRepository([Iterable<Contractor> seed = const []])
      : _store = InMemoryCollection(seed, (c) => c.id);

  final InMemoryCollection<Contractor> _store;

  @override
  Stream<List<Contractor>> watchAll() => _store.watch();

  @override
  Future<List<Contractor>> listContractors() async => _store.snapshot;

  @override
  Future<Contractor?> findById(String id) async => _store.find(id);

  @override
  Future<void> save(Contractor contractor) async => _store.upsert(contractor);
}
