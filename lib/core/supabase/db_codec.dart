import '../../features/complaints/domain/complaint.dart';
import '../../features/complaints/domain/services/priority_engine.dart';
import '../../features/jobs/domain/contractor.dart';
import '../../features/jobs/domain/work_job.dart';
import '../models/app_role.dart';

class DbCodec {
  const DbCodec._();

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

  static AppRole roleForStatus(ComplaintStatus s) => switch (s) {
        ComplaintStatus.draft || ComplaintStatus.submitted => AppRole.citizen,
        ComplaintStatus.inProgress ||
        ComplaintStatus.awaitingInspection =>
          AppRole.contractor,
        _ => AppRole.municipalAdmin,
      };

  static PriorityLevel priorityFrom(String? v) => switch (v) {
        'low' => PriorityLevel.low,
        'high' => PriorityLevel.high,
        'critical' => PriorityLevel.critical,
        _ => PriorityLevel.medium,
      };

  static AppRole? roleFrom(String? v) => switch (v) {
        'citizen' => AppRole.citizen,
        'contractor' => AppRole.contractor,
        'municipal_admin' => AppRole.municipalAdmin,
        _ => null,
      };

  static ContractorStatus contractorStatusFrom(String? v) => switch (v) {
        'approved' => ContractorStatus.approved,
        'rejected' => ContractorStatus.rejected,
        _ => ContractorStatus.pendingApproval,
      };

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

  static PaymentStatus paymentFrom(String? v) => switch (v) {
        'authorized' => PaymentStatus.heldSimulated,
        'simulated_paid' => PaymentStatus.releasedSimulated,
        _ => PaymentStatus.notStarted,
      };

  static String jobRef(String uuid) => 'JOB-${_short(uuid)}';

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
