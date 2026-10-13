import 'contractor.dart';
import 'work_job.dart';

abstract class JobRepository {
  Stream<List<WorkJob>> watchAll();
  Future<List<WorkJob>> listJobs();
  Future<WorkJob?> findById(String id);
  Future<String> nextId();

  Future<void> save(WorkJob job);
}

abstract class ContractorRepository {
  Stream<List<Contractor>> watchAll();
  Future<List<Contractor>> listContractors();
  Future<Contractor?> findById(String id);
  Future<void> save(Contractor contractor);
}
