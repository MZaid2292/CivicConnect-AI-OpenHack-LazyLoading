import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../../jobs/domain/contractor.dart';
import '../../../jobs/domain/job_service.dart';
import '../../../jobs/domain/work_job.dart';
import '../../../jobs/presentation/cubit/job_list_cubits.dart';
import '../../../jobs/presentation/widgets/job_card.dart';

class WorkTab extends StatelessWidget {
  const WorkTab({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          Material(
            color: context.colors.surface,
            child: const TabBar(tabs: [
              Tab(icon: Icon(Icons.work_outline), text: 'Jobs & tenders'),
              Tab(icon: Icon(Icons.engineering_outlined), text: 'Contractors'),
            ]),
          ),
          const Expanded(
            child: TabBarView(children: [_JobsList(), _ContractorsList()]),
          ),
        ]),
      );
}

class _JobsList extends StatefulWidget {
  const _JobsList();
  @override
  State<_JobsList> createState() => _JobsListState();
}

class _JobsListState extends State<_JobsList> {
  static const _filters = <String, Set<JobStatus>>{
    'Active': {
      JobStatus.awarded,
      JobStatus.inProgress,
      JobStatus.completionSubmitted,
      JobStatus.reworkRequested,
    },
    'Tenders': {JobStatus.openForBids},
    'Completed': {JobStatus.completed, JobStatus.cancelled},
  };
  String _filter = 'Active';

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<JobsCubit, DataState<List<WorkJob>>>(
        builder: (context, state) {
          if (state.status == LoadStatus.loading) {
            return const CivicLoadingState();
          }
          if (state.status == LoadStatus.failure) {
            return CivicErrorState(
                message: state.error!,
                onRetry: context.read<JobsCubit>().retry);
          }
          final all = state.data!;
          final jobs =
              all.where((j) => _filters[_filter]!.contains(j.status)).toList();
          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                      for (final f in _filters.keys)
                        ChoiceChip(
                          showCheckmark: false,
                          label: Text(
                              '$f (${all.where((j) => _filters[f]!.contains(j.status)).length})'),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ]),
                    Space.gapLg,
                    if (jobs.isEmpty)
                      const CivicEmptyState(
                          icon: Icons.work_off_outlined,
                          title: 'No jobs here',
                          message: 'Verify a report, then assign a contractor '
                              'or open a tender from its detail page.')
                    else
                      AdaptiveGrid(minTileWidth: 380, children: [
                        for (final j in jobs)
                          JobCard(
                              job: j,
                              highlight:
                                  j.status == JobStatus.completionSubmitted
                                      ? 'Ready for inspection'
                                      : null,
                              onTap: () => context.push(Routes.job(j.id))),
                      ]),
                  ]),
            ),
          );
        },
      );
}

class _ContractorsList extends StatelessWidget {
  const _ContractorsList();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ContractorsCubit, DataState<List<Contractor>>>(
        builder: (context, state) {
          if (state.status == LoadStatus.loading) {
            return const CivicLoadingState();
          }
          if (state.status == LoadStatus.failure) {
            return CivicErrorState(message: state.error!);
          }
          final list = [...state.data!]
            ..sort((a, b) => a.status.index.compareTo(b.status.index));
          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdaptiveGrid(minTileWidth: 380, children: [
                      for (final c in list) _ContractorCard(contractor: c),
                    ]),
                  ]),
            ),
          );
        },
      );
}

class _ContractorCard extends StatelessWidget {
  const _ContractorCard({required this.contractor});
  final Contractor contractor;

  Color get _color => switch (contractor.status) {
        ContractorStatus.approved => AppColors.teal,
        ContractorStatus.pendingApproval => AppColors.amber,
        ContractorStatus.rejected => AppColors.red,
        ContractorStatus.suspended => AppColors.slate,
      };

  Future<void> _set(BuildContext context, ContractorStatus status) async {
    try {
      await context.read<JobService>().setContractorStatus(
          context.read<SessionCubit>().state.actor!, contractor.id, status);
      if (context.mounted) {
        showMessage(context, '${contractor.name}: ${status.label}.');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = contractor;
    return CivicCard(
      borderColor: c.status == ContractorStatus.pendingApproval
          ? context.civic.tone(AppColors.amber).withValues(alpha: 0.5)
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CivicAvatar(name: c.name, radius: 22),
          Space.gapMd,
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: context.textStyles.titleMedium),
              Text(
                  'Reg. ${c.registrationNo} · joined ${formatDate(c.joinedAt)}',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.civic.muted)),
            ]),
          ),
          Space.gapSm,
          Flexible(child: Pill(label: c.status.label, color: _color)),
        ]),
        Space.gapMd,
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in c.specialties)
            Pill(label: s.shortLabel, color: AppColors.civicBlue, icon: s.icon),
          Pill(
              label: c.averageRating == null
                  ? 'No ratings'
                  : '★ ${c.averageRating!.toStringAsFixed(1)} (${c.ratingCount})',
              color: AppColors.amber),
          Pill(label: '${c.completedJobs} jobs done', color: AppColors.teal),
        ]),
        Space.gapMd,
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          if (c.status == ContractorStatus.pendingApproval) ...[
            FilledButton(
                onPressed: () => _set(context, ContractorStatus.approved),
                child: const Text('Approve')),
            CivicButton(
                variant: CivicButtonVariant.danger,
                onPressed: () => _set(context, ContractorStatus.rejected),
                label: 'Reject'),
          ],
          if (c.status == ContractorStatus.approved)
            TextButton(
                onPressed: () => _set(context, ContractorStatus.suspended),
                child: const Text('Suspend')),
          if (c.status == ContractorStatus.suspended ||
              c.status == ContractorStatus.rejected)
            OutlinedButton(
                onPressed: () => _set(context, ContractorStatus.approved),
                child: const Text('Reinstate')),
        ]),
      ]),
    );
  }
}
