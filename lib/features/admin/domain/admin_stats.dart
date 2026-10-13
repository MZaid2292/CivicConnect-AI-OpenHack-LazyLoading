import '../../complaints/domain/complaint.dart';
import '../../complaints/domain/services/priority_engine.dart';
import '../../jobs/domain/contractor.dart';
import '../../jobs/domain/work_job.dart';

class AdminStats {
  AdminStats({
    required List<Complaint> complaints,
    required List<WorkJob> jobs,
    required List<Contractor> contractors,
    required DateTime now,
  }) {
    final public = complaints.where((c) => c.status.isPublic).toList();
    awaitingVerification = public
        .where((c) =>
            c.status == ComplaintStatus.submitted ||
            c.status == ComplaintStatus.underReview)
        .toList()
      ..sort((a, b) => b.priority.score.compareTo(a.priority.score));
    open = public.where((c) => c.status.isOpen).length;
    urgent = public
        .where((c) =>
            c.status.isOpen &&
            (c.priority.level == PriorityLevel.critical ||
                c.priority.level == PriorityLevel.high))
        .toList()
      ..sort((a, b) => b.priority.score.compareTo(a.priority.score));
    awaitingInspection =
        jobs.where((j) => j.status == JobStatus.completionSubmitted).toList();
    openTenders = jobs.where((j) => j.status == JobStatus.openForBids).toList();
    activeJobs = jobs.where((j) => j.status.isActive).length;
    pendingContractors = contractors
        .where((c) => c.status == ContractorStatus.pendingApproval)
        .toList();
    final weekAgo = now.subtract(const Duration(days: 7));
    resolvedThisWeek = public
        .where((c) =>
            c.status == ComplaintStatus.resolved &&
            c.updatedAt.isAfter(weekAgo))
        .length;
    final ratings = [
      for (final c in public)
        if (c.feedback != null) c.feedback!.rating
    ];
    averageRating = ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;
    byCategory = {
      for (final cat in ComplaintCategory.values)
        cat: public.where((c) => c.category == cat && c.status.isOpen).length,
    };
  }

  late final List<Complaint> awaitingVerification;
  late final int open;
  late final List<Complaint> urgent;
  late final List<WorkJob> awaitingInspection;
  late final List<WorkJob> openTenders;
  late final int activeJobs;
  late final List<Contractor> pendingContractors;
  late final int resolvedThisWeek;
  late final double? averageRating;
  late final Map<ComplaintCategory, int> byCategory;
}
