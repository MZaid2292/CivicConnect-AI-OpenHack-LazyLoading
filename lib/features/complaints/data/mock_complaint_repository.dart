import 'dart:async';

import '../../../core/data/in_memory_collection.dart';
import '../../../core/models/workflow_exception.dart';
import '../domain/complaint.dart';
import '../domain/complaint_repository.dart';
import '../domain/complaint_workflow.dart';
import '../domain/priority_rules_repository.dart';
import '../domain/services/priority_engine.dart';

class MockComplaintRepository implements ComplaintRepository {
  MockComplaintRepository([Iterable<Complaint> seed = const []])
      : _store = InMemoryCollection(seed, (c) => c.id),
        _counter = 1000 + seed.length + 1;

  final InMemoryCollection<Complaint> _store;
  int _counter;

  @override
  Stream<List<Complaint>> watchAll() => _store.watch();

  @override
  Future<List<Complaint>> listComplaints() async => _store.snapshot;

  @override
  Future<Complaint?> findById(String id) async => _store.find(id);

  @override
  Future<String> nextId() async {
    while (_store.find('CMP-$_counter') != null) {
      _counter++;
    }
    return 'CMP-${_counter++}';
  }

  @override
  Future<void> save(Complaint complaint) async {
    _guard(complaint);
    _store.upsert(complaint);
  }

  @override
  Future<void> saveAll(Iterable<Complaint> complaints) async {
    for (final c in complaints) {
      _guard(c);
      _store.upsert(c, notify: false);
    }
    _store.notify();
  }

  void _guard(Complaint next) {
    final existing = _store.find(next.id);
    if (existing == null) {
      if (next.status != ComplaintStatus.draft &&
          next.status != ComplaintStatus.submitted) {
        throw const WorkflowException(
            'New complaints must start as Draft or Submitted.');
      }
      return;
    }
    if (existing.status != next.status &&
        !ComplaintWorkflow.isValidTransition(existing.status, next.status)) {
      throw WorkflowException(
          'Illegal transition ${existing.status.label} → ${next.status.label}.');
    }
  }
}

class InMemoryPriorityRulesRepository implements PriorityRulesRepository {
  InMemoryPriorityRulesRepository([PriorityRules? initial])
      : _current = initial ?? PriorityRules.defaults;

  PriorityRules _current;
  final _changes = StreamController<PriorityRules>.broadcast();

  @override
  PriorityRules get current => _current;

  @override
  Stream<PriorityRules> watch() => Stream.multi((controller) {
        controller.add(_current);
        final sub = _changes.stream.listen(controller.add);
        controller.onCancel = sub.cancel;
      });

  @override
  Future<void> save(PriorityRules rules) async {
    if (!rules.thresholdsValid) {
      throw const WorkflowException(
          'Thresholds must increase: Medium < High < Critical.');
    }
    _current = rules;
    _changes.add(rules);
  }
}
