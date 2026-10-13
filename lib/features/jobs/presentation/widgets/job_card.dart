import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../domain/work_job.dart';

/// Marketplace-style job card: category, title, money and bid activity.
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, this.onTap, this.highlight});
  final WorkJob job;
  final VoidCallback? onTap;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    final amount = job.awardedAmount ?? job.budgetEstimate;
    return CivicCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CivicIconBadge(icon: job.category.icon, size: 44),
          Space.gapMd,
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${job.id} · ${job.complaintId} · ${job.department}',
                  maxLines: adaptiveLines(context),
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelSmall
                      ?.copyWith(color: civic.muted)),
              const SizedBox(height: 2),
              Text(job.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.titleMedium),
            ]),
          ),
        ]),
        Space.gapMd,
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(job.awardedAmount != null ? 'Agreed' : 'Budget',
                      style: context.textStyles.labelSmall
                          ?.copyWith(color: civic.muted)),
                  Text(formatAmount(amount),
                      style: context.textStyles.titleMedium
                          ?.copyWith(color: context.colors.primary)),
                ]),
            JobStatusChip(job.status),
            if (job.status == JobStatus.openForBids)
              Pill(
                  label:
                      '${job.bids.length} bid${job.bids.length == 1 ? '' : 's'}',
                  color: AppColors.indigo,
                  icon: Icons.gavel_outlined),
            if (job.contractorName != null)
              Pill(
                  label: job.contractorName!,
                  color: AppColors.teal,
                  icon: Icons.engineering_outlined),
          ],
        ),
        if (highlight != null) ...[
          Space.gapMd,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: Radii.brSm),
            child: Row(children: [
              Icon(Icons.arrow_forward,
                  size: 16, color: context.colors.onPrimaryContainer),
              Space.gapSm,
              Expanded(
                child: Text(highlight!,
                    style: context.textStyles.labelLarge
                        ?.copyWith(color: context.colors.onPrimaryContainer)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
