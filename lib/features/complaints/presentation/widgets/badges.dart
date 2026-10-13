import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../jobs/domain/work_job.dart';
import '../../domain/complaint.dart';
import '../../domain/services/priority_engine.dart';

extension ComplaintStatusStyle on ComplaintStatus {
  Color get color => switch (this) {
        ComplaintStatus.draft => AppColors.slate,
        ComplaintStatus.submitted => AppColors.cyan,
        ComplaintStatus.verified => AppColors.royal,
        ComplaintStatus.assigned => AppColors.indigo,
        ComplaintStatus.inProgress => AppColors.amber,
        ComplaintStatus.awaitingInspection => AppColors.purple,
        ComplaintStatus.reworkRequired => AppColors.orange,
        ComplaintStatus.resolved => AppColors.teal,
        ComplaintStatus.rejected => AppColors.red,
        ComplaintStatus.duplicate => AppColors.slate,
      };

  IconData get icon => switch (this) {
        ComplaintStatus.draft => Icons.edit_note,
        ComplaintStatus.submitted => Icons.outbox_outlined,
        ComplaintStatus.verified => Icons.verified_outlined,
        ComplaintStatus.assigned => Icons.assignment_ind_outlined,
        ComplaintStatus.inProgress => Icons.construction,
        ComplaintStatus.awaitingInspection => Icons.fact_check_outlined,
        ComplaintStatus.reworkRequired => Icons.replay,
        ComplaintStatus.resolved => Icons.check_circle_outline,
        ComplaintStatus.rejected => Icons.block,
        ComplaintStatus.duplicate => Icons.merge_type,
      };
}

extension ComplaintCategoryStyle on ComplaintCategory {
  IconData get icon => switch (this) {
        ComplaintCategory.roadDamage => Icons.add_road,
        ComplaintCategory.streetlight => Icons.light_outlined,
        ComplaintCategory.garbage => Icons.delete_outline,
        ComplaintCategory.drainage => Icons.water_drop_outlined,
        ComplaintCategory.other => Icons.report_outlined,
      };
}

extension PriorityLevelStyle on PriorityLevel {
  Color get color => switch (this) {
        PriorityLevel.low => AppColors.green,
        PriorityLevel.medium => AppColors.amber,
        PriorityLevel.high => AppColors.orange,
        PriorityLevel.critical => AppColors.red,
      };
}

extension JobStatusStyle on JobStatus {
  Color get color => switch (this) {
        JobStatus.openForBids => AppColors.royal,
        JobStatus.awarded => AppColors.indigo,
        JobStatus.inProgress => AppColors.amber,
        JobStatus.completionSubmitted => AppColors.purple,
        JobStatus.reworkRequested => AppColors.orange,
        JobStatus.completed => AppColors.teal,
        JobStatus.cancelled => AppColors.slate,
      };
}

class CivicStatusBadge extends StatelessWidget {
  const CivicStatusBadge(this.status, {super.key});
  final ComplaintStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Status ${status.label}',
        child:
            Pill(label: status.label, color: status.color, icon: status.icon),
      );
}

class JobStatusChip extends StatelessWidget {
  const JobStatusChip(this.status, {super.key});
  final JobStatus status;

  @override
  Widget build(BuildContext context) =>
      Pill(label: status.label, color: status.color, icon: Icons.work_outline);
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.assessment, {super.key, this.showScore = true});
  final PriorityAssessment assessment;
  final bool showScore;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: assessment.explanation,
        child: Pill(
          label: showScore
              ? '${assessment.level.label} · ${assessment.score}'
              : assessment.level.label,
          color: assessment.level.color,
          icon: Icons.flag_outlined,
        ),
      );
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(this.category, {super.key});
  final ComplaintCategory category;

  @override
  Widget build(BuildContext context) => Pill(
      label: category.shortLabel,
      color: AppColors.civicBlue,
      icon: category.icon);
}
