import 'complaint.dart';

/// Storage contract. The mock implementation lives in memory; a Supabase
/// implementation can replace it without touching presentation code.
abstract class ComplaintRepository {
  /// Emits the current list immediately and again after every change.
  Stream<List<Complaint>> watchAll();
  Future<List<Complaint>> listComplaints();
  Future<Complaint?> findById(String id);
  Future<String> nextId();

  /// Inserts or updates. Implementations must reject illegal status changes.
  Future<void> save(Complaint complaint);
  Future<void> saveAll(Iterable<Complaint> complaints);
}
