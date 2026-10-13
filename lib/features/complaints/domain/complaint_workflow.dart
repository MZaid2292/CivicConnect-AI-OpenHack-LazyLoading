import '../../../core/models/app_role.dart';
import '../../../core/models/workflow_exception.dart';
import 'complaint.dart';

/// Explicit complaint state machine: which transitions exist and which role
/// may trigger each. Shared by the mock repository (state check) and the
/// domain services (state + role check) so a future Supabase backend can mirror
/// the same table in RLS / database functions.
class ComplaintWorkflow {
  const ComplaintWorkflow._();

  static const _citizen = {AppRole.citizen};
  static const _admin = {AppRole.municipalAdmin};
  static const _contractor = {AppRole.contractor};

  static const Map<ComplaintStatus, Map<ComplaintStatus, Set<AppRole>>>
      transitions = {
    ComplaintStatus.draft: {ComplaintStatus.submitted: _citizen},
    ComplaintStatus.submitted: {
      ComplaintStatus.verified: _admin,
      ComplaintStatus.rejected: _admin,
      ComplaintStatus.duplicate: _admin,
    },
    ComplaintStatus.verified: {
      ComplaintStatus.assigned: _admin,
      ComplaintStatus.rejected: _admin,
      ComplaintStatus.duplicate: _admin,
    },
    ComplaintStatus.assigned: {ComplaintStatus.inProgress: _contractor},
    ComplaintStatus.inProgress: {
      ComplaintStatus.awaitingInspection: _contractor,
    },
    ComplaintStatus.awaitingInspection: {
      ComplaintStatus.resolved: _admin,
      ComplaintStatus.reworkRequired: _admin,
    },
    ComplaintStatus.reworkRequired: {ComplaintStatus.inProgress: _contractor},
    ComplaintStatus.resolved: {},
    ComplaintStatus.rejected: {},
    ComplaintStatus.duplicate: {},
  };

  /// Pure state check (no role).
  static bool isValidTransition(ComplaintStatus from, ComplaintStatus to) =>
      transitions[from]?.containsKey(to) ?? false;

  static bool canTransition(
          ComplaintStatus from, ComplaintStatus to, AppRole role) =>
      transitions[from]?[to]?.contains(role) ?? false;

  static void ensure(ComplaintStatus from, ComplaintStatus to, AppRole role) {
    if (!isValidTransition(from, to)) {
      throw WorkflowException(
          'Cannot move a complaint from "${from.label}" to "${to.label}".');
    }
    if (!canTransition(from, to, role)) {
      throw WorkflowException(
          '${role.label} is not allowed to mark a complaint "${to.label}".');
    }
  }

  static Iterable<ComplaintStatus> nextFor(
          ComplaintStatus from, AppRole role) =>
      (transitions[from] ?? const {})
          .entries
          .where((e) => e.value.contains(role))
          .map((e) => e.key);

  /// The "happy path" used to draw progress in the status tracker.
  static const happyPath = [
    ComplaintStatus.submitted,
    ComplaintStatus.verified,
    ComplaintStatus.assigned,
    ComplaintStatus.inProgress,
    ComplaintStatus.awaitingInspection,
    ComplaintStatus.resolved,
  ];
}
