import 'complaint.dart';

abstract class ComplaintRepository {
  Stream<List<Complaint>> watchAll();
  Future<List<Complaint>> listComplaints();
  Future<Complaint?> findById(String id);
  Future<String> nextId();

  Future<void> save(Complaint complaint);
  Future<void> saveAll(Iterable<Complaint> complaints);
}
