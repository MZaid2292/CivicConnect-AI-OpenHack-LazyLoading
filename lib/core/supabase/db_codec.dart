import '../../features/complaints/domain/complaint.dart';
import '../../features/complaints/domain/services/priority_engine.dart';
import '../../features/jobs/domain/contractor.dart';
import '../../features/jobs/domain/work_job.dart';
import '../models/app_role.dart';

/// Pure mappings between PostgreSQL values (see supabase/schema_inspection.json)
/// and the app's domain enums. No I/O, so they are unit tested directly.
class DbCodec {
  const DbCodec._();

  // ---- complaints.category ------------------------------------------------
  // CHECK: pothole | streetlight | garbage | other (+ drainage once the
  // pending migration is applied).

  static String category(ComplaintCategory c) => switch (c) {
        ComplaintCategory.roadDamage => 'pothole',
        ComplaintCategory.streetlight => 'streetlight',
        ComplaintCategory.garbage => 'garbage',
        ComplaintCategory.drainage => 'drainage',
        ComplaintCategory.other => 'other',
      };

  static ComplaintCategory categoryFrom(String? v) => switch (v) {
        'pothole' => ComplaintCategory.roadDamage,
        'streetlight' => ComplaintCategory.streetlight,
        'garbage' => ComplaintCategory.garbage,
        'drainage' => ComplaintCategory.drainage,
        _ => ComplaintCategory.other,
      };

  // ---- complaints.status ----------------------------------------------------
  // CHECK: submitted | under_review | verified | rejected | assigned |
  // in_progress | awaiting_inspection | rework_required | resolved | reopened

  static ComplaintStatus statusFrom(String? v, {bool linkedDuplicate = false}) {
    if (linkedDuplicate) return ComplaintStatus.duplicate;
    return switch (v) {
      'under_review' => ComplaintStatus.underReview,
      'verified' => ComplaintStatus.verified,
      'rejected' => ComplaintStatus.rejected,
      'assigned' => ComplaintStatus.assigned,
      'in_progress' => ComplaintStatus.inProgress,
      'awaiting_inspection' => ComplaintStatus.awaitingInspection,
      'rework_required' => ComplaintStatus.reworkRequired,
      'resolved' => ComplaintStatus.resolved,
      // A reopened report is back in the municipality's intake queue.
      'reopened' => ComplaintStatus.submitted,
      _ => ComplaintStatus.submitted,
    };
  }

  static String status(ComplaintStatus s) => switch (s) {
        ComplaintStatus.underReview => 'under_review',
        ComplaintStatus.verified => 'verified',
        ComplaintStatus.rejected => 'rejected',
        ComplaintStatus.assigned => 'assigned',
        ComplaintStatus.inProgress => 'in_progress',
        ComplaintStatus.awaitingInspection => 'awaiting_inspection',
        ComplaintStatus.reworkRequired => 'rework_required',
        ComplaintStatus.resolved => 'resolved',
        ComplaintStatus.submitted ||
        ComplaintStatus.draft ||
        ComplaintStatus.duplicate =>
          'submitted',
      };

  /// Which role performs a transition into [s] — every complaint transition
  /// is gated to exactly one role by the database functions, so the role of
  /// a history entry can be stated even when the actor's name is private.
  static AppRole roleForStatus(ComplaintStatus s) => switch (s) {
        ComplaintStatus.draft || ComplaintStatus.submitted => AppRole.citizen,
        ComplaintStatus.inProgress ||
        ComplaintStatus.awaitingInspection =>
          AppRole.contractor,
        _ => AppRole.municipalAdmin,
      };

  // ---- complaints.priority ------------------------------------------------

  static PriorityLevel priorityFrom(String? v) => switch (v) {
        'low' => PriorityLevel.low,
        'high' => PriorityLevel.high,
        'critical' => PriorityLevel.critical,
        _ => PriorityLevel.medium,
      };

  // ---- profiles.role ----------------------------------------------------------
  // CHECK: citizen | contractor | municipal_admin | inspector | finance

  /// Maps a trusted database role to an app dashboard. Inspector and finance
  /// accounts have no dashboard in this app, so they map to null.
  static AppRole? roleFrom(String? v) => switch (v) {
        'citizen' => AppRole.citizen,
        'contractor' => AppRole.contractor,
        'municipal_admin' => AppRole.municipalAdmin,
        _ => null,
      };

  // ---- contractors.verification_status ---------------------------------------

  static ContractorStatus contractorStatusFrom(String? v) => switch (v) {
        'approved' => ContractorStatus.approved,
        'rejected' => ContractorStatus.rejected,
        _ => ContractorStatus.pendingApproval,
      };

  // ---- jobs.status + contracts.status → JobStatus ------------------------------

  static JobStatus jobStatusFrom(
      {required String? job, required String? contract}) {
    if (job == 'cancelled' || contract == 'cancelled') {
      return JobStatus.cancelled;
    }
    return switch (contract) {
      'awarded' => JobStatus.awarded,
      'in_progress' => JobStatus.inProgress,
      'submitted' => JobStatus.completionSubmitted,
      'rework' => JobStatus.reworkRequested,
      'accepted' => JobStatus.completed,
      _ => job == 'awarded' ? JobStatus.awarded : JobStatus.openForBids,
    };
  }

  // ---- payments.status (simulation only) ------------------------------------

  static PaymentStatus paymentFrom(String? v) => switch (v) {
        'authorized' => PaymentStatus.heldSimulated,
        'simulated_paid' => PaymentStatus.releasedSimulated,
        _ => PaymentStatus.notStarted,
      };

  // ---- display ids -------------------------------------------------------------

  /// Short, stable display id for a job uuid (jobs have no reference code).
  static String jobRef(String uuid) => 'JOB-${_short(uuid)}';

  /// Short display code for a contractor uuid.
  static String contractorRef(String uuid) => 'CTR-${_short(uuid)}';

  static String _short(String id) {
    final compact = id.replaceAll('-', '');
    return (compact.length > 8 ? compact.substring(0, 8) : compact)
        .toUpperCase();
  }

  static DateTime time(Object? v) =>
      v is String ? DateTime.parse(v).toLocal() : DateTime.now();

  static int toInt(Object? v) => switch (v) {
        int i => i,
        double d => d.round(),
        String s => double.tryParse(s)?.round() ?? 0,
        _ => 0,
      };

  static double? toDouble(Object? v) => switch (v) {
        int i => i.toDouble(),
        double d => d,
        String s => double.tryParse(s),
        _ => null,
      };
}
