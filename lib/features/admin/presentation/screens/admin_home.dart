import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/models/app_role.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/complaint_repository.dart';
import '../../../complaints/domain/services/complaint_service.dart';
import '../../../complaints/presentation/cubit/complaint_list_cubit.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../../complaints/presentation/widgets/complaint_list_view.dart';
import '../../../jobs/domain/job_repositories.dart';
import '../../../jobs/presentation/cubit/job_list_cubits.dart';
import '../../../shell/presentation/role_shell.dart';
import '../../domain/admin_stats.dart';
import '../cubit/duplicate_review_cubit.dart';
import '../cubit/priority_rules_cubit.dart';
import 'duplicate_review_tab.dart';
import 'priority_rules_tab.dart';
import 'work_tab.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    final complaints = context.read<ComplaintRepository>();
    final jobs = context.read<JobRepository>();
    final contractors = context.read<ContractorRepository>();
    final service = context.read<ComplaintService>();
    final actor = context.read<SessionCubit>().state.actor!;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ComplaintListCubit(complaints)),
        BlocProvider(create: (_) => JobsCubit(jobs.watchAll)),
        BlocProvider(create: (_) => ContractorsCubit(contractors.watchAll)),
        BlocProvider(
            create: (_) => DuplicateReviewCubit(
                complaints: complaints, service: service, actor: actor)),
        BlocProvider(
            create: (_) => PriorityRulesCubit(
                service: service, complaints: complaints, actor: actor)),
      ],
      child: const RoleShell(role: AppRole.municipalAdmin, tabs: [
        ShellTab(
          label: 'Overview',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          child: AdminOverviewTab(),
        ),
        ShellTab(
          label: 'Queue',
          title: 'Complaint queue',
          icon: Icons.inbox_outlined,
          selectedIcon: Icons.inbox,
          child: AdminQueueTab(),
        ),
        ShellTab(
          label: 'Duplicates',
          title: 'Duplicate review',
          icon: Icons.merge_type_outlined,
          selectedIcon: Icons.merge_type,
          child: DuplicateReviewTab(),
        ),
        ShellTab(
          label: 'Work',
          title: 'Jobs & contractors',
          icon: Icons.handyman_outlined,
          selectedIcon: Icons.handyman,
          child: WorkTab(),
        ),
        ShellTab(
          label: 'Rules',
          title: 'Priority rules',
          icon: Icons.tune_outlined,
          selectedIcon: Icons.tune,
          child: PriorityRulesTab(),
        ),
      ]),
    );
  }
}

class AdminOverviewTab extends StatelessWidget {
  const AdminOverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final complaints = context.watch<ComplaintListCubit>().state;
    final jobs = context.watch<JobsCubit>().state;
    final contractors = context.watch<ContractorsCubit>().state;
    final duplicates = context.watch<DuplicateReviewCubit>().state;
    if (complaints.status == LoadStatus.loading ||
        jobs.status == LoadStatus.loading ||
        contractors.status == LoadStatus.loading) {
      return const CivicLoadingState(label: 'Loading dashboard…');
    }
    if (complaints.status == LoadStatus.failure ||
        jobs.status == LoadStatus.failure) {
      return CivicErrorState(
          message: complaints.error ?? jobs.error ?? 'Could not load data.',
          onRetry: () {
            context.read<ComplaintListCubit>().retry();
            context.read<JobsCubit>().retry();
          });
    }
    final stats = AdminStats(
      complaints: complaints.all,
      jobs: jobs.data!,
      contractors: contractors.data ?? const [],
      now: DateTime.now(),
    );
    final goTo = ShellScope.maybeOf(context)?.goToTab;
    final maxCat =
        stats.byCategory.values.fold<int>(1, (a, b) => b > a ? b : a);

    final inspection = _Panel(
      title: 'Ready for inspection',
      icon: Icons.fact_check_outlined,
      empty: 'No contractor submissions waiting.',
      children: [
        for (final j in stats.awaitingInspection)
          _PanelRow(
            leading: const CivicIconBadge(
                icon: Icons.fact_check_outlined,
                color: AppColors.purple,
                size: 36),
            title: '${j.id} · ${j.title}',
            subtitle: j.contractorName ?? '',
            trailing: FilledButton(
                onPressed: () => context.push(Routes.inspect(j.id)),
                child: const Text('Inspect')),
          ),
      ],
    );
    final urgent = _Panel(
      title: 'Highest priority',
      icon: Icons.priority_high,
      empty: 'Nothing urgent right now.',
      action: TextButton(
          onPressed: () => goTo?.call(1), child: const Text('Open queue')),
      children: [
        for (final c in stats.urgent.take(5))
          _PanelRow(
            onTap: () => context.push(Routes.complaint(c.id)),
            leading: CivicIconBadge(
                icon: c.category.icon, color: c.priority.level.color, size: 36),
            title: '${c.id} · ${c.title}',
            subtitle: c.status.label,
            trailing: PriorityBadge(c.priority),
          ),
      ],
    );
    final categories = _Panel(
      title: 'Open reports by category',
      icon: Icons.donut_small_outlined,
      empty: '',
      children: [
        for (final e in stats.byCategory.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(e.key.icon, size: 18, color: context.civic.muted),
              Space.gapSm,
              SizedBox(
                  width: MediaQuery.textScalerOf(context)
                      .scale(96)
                      .clamp(96.0, 140.0),
                  child: Text(e.key.shortLabel,
                      maxLines: adaptiveLines(context),
                      overflow: TextOverflow.ellipsis)),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: e.value / maxCat),
                  duration: Motion.of(context, Motion.slow),
                  curve: Motion.curve,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              Space.gapSm,
              SizedBox(
                  width: 24,
                  child: Text('${e.value}',
                      textAlign: TextAlign.end,
                      style: context.textStyles.labelLarge)),
            ]),
          ),
      ],
    );
    final approvals = _Panel(
      title: 'Contractor approvals',
      icon: Icons.how_to_reg_outlined,
      empty: 'No pending registrations.',
      children: [
        for (final ctr in stats.pendingContractors)
          _PanelRow(
            leading: CivicAvatar(name: ctr.name),
            title: ctr.name,
            subtitle: 'Reg. ${ctr.registrationNo}',
            trailing: OutlinedButton(
                onPressed: () => goTo?.call(3), child: const Text('Review')),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: pagePadding(context),
      child: ResponsiveCenter(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CivicHeroCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  style: context.textStyles.labelMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
              Space.gapXs,
              Text(
                  context.isLiveBackend
                      ? '${context.read<SessionCubit>().state.profile?.municipalityName ?? 'Municipal'} operations'
                      : 'Ward 4 operations',
                  style: context.textStyles.headlineSmall
                      ?.copyWith(color: Colors.white)),
              Space.gapXs,
              Text(
                  '${stats.awaitingVerification.length} reports to verify · '
                  '${stats.awaitingInspection.length} ready for inspection · '
                  '${duplicates.items.length} possible duplicates',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
              Space.gapLg,
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                _HeroAction(
                    icon: Icons.inbox_outlined,
                    label: 'Review queue',
                    onTap: () => goTo?.call(1)),
                _HeroAction(
                    icon: Icons.merge_type,
                    label: 'Duplicates',
                    onTap: () => goTo?.call(2)),
                _HeroAction(
                    icon: Icons.tune,
                    label: 'Tune rules',
                    onTap: () => goTo?.call(4)),
              ]),
            ]),
          ),
          Space.gapLg,
          AdaptiveGrid(minTileWidth: 210, children: [
            CivicStatCard(
                label: 'Awaiting verification',
                value: '${stats.awaitingVerification.length}',
                icon: Icons.outbox_outlined,
                onTap: () => goTo?.call(1)),
            CivicStatCard(
                label: 'High / critical open',
                value: '${stats.urgent.length}',
                icon: Icons.priority_high,
                color: AppColors.red,
                onTap: () => goTo?.call(1)),
            CivicStatCard(
                label: 'Possible duplicates',
                value: '${duplicates.items.length}',
                icon: Icons.merge_type,
                color: AppColors.orange,
                onTap: () => goTo?.call(2)),
            CivicStatCard(
                label: 'Awaiting inspection',
                value: '${stats.awaitingInspection.length}',
                icon: Icons.fact_check_outlined,
                color: AppColors.purple),
            CivicStatCard(
                label: 'Active jobs',
                value: '${stats.activeJobs}',
                icon: Icons.construction,
                color: AppColors.amber,
                caption: '${stats.openTenders.length} open tenders',
                onTap: () => goTo?.call(3)),
            CivicStatCard(
                label: 'Resolved this week',
                value: '${stats.resolvedThisWeek}',
                icon: Icons.check_circle_outline,
                color: AppColors.teal,
                caption: stats.averageRating == null
                    ? null
                    : '★ ${stats.averageRating!.toStringAsFixed(1)} avg rating'),
          ]),
          Space.gapLg,
          _StatusDistribution(complaints: complaints.all),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 760) {
              return Column(
                  children: [inspection, urgent, categories, approvals]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [inspection, urgent])),
              Space.gapLg,
              Expanded(child: Column(children: [categories, approvals])),
            ]);
          }),
        ]),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          minimumSize: const Size(0, 44),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

/// Pending vs resolved overview as one segmented bar with a legend.
class _StatusDistribution extends StatelessWidget {
  const _StatusDistribution({required this.complaints});
  final List<Complaint> complaints;

  @override
  Widget build(BuildContext context) {
    final public = complaints.where((c) => c.status.isPublic).toList();
    final groups = <(String, Color, int)>[
      (
        'New',
        AppColors.cyan,
        public
            .where((c) =>
                c.status == ComplaintStatus.submitted ||
                c.status == ComplaintStatus.underReview)
            .length
      ),
      (
        'Verified / assigned',
        AppColors.civicBlue,
        public
            .where((c) =>
                c.status == ComplaintStatus.verified ||
                c.status == ComplaintStatus.assigned)
            .length
      ),
      (
        'In work',
        AppColors.amber,
        public
            .where((c) =>
                c.status == ComplaintStatus.inProgress ||
                c.status == ComplaintStatus.reworkRequired ||
                c.status == ComplaintStatus.awaitingInspection)
            .length
      ),
      (
        'Resolved',
        AppColors.teal,
        public.where((c) => c.status == ComplaintStatus.resolved).length
      ),
      (
        'Closed other',
        AppColors.slate,
        public
            .where((c) =>
                c.status == ComplaintStatus.rejected ||
                c.status == ComplaintStatus.duplicate)
            .length
      ),
    ];
    final total = public.isEmpty ? 1 : public.length;
    final civic = context.civic;
    return CivicCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Pending vs resolved',
                  style: context.textStyles.titleSmall)),
          Text('${public.length} reports',
              style:
                  context.textStyles.labelMedium?.copyWith(color: civic.muted)),
        ]),
        Space.gapMd,
        Semantics(
          label: groups.map((g) => '${g.$1}: ${g.$3}').join(', '),
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                for (final g in groups)
                  if (g.$3 > 0)
                    Expanded(
                      flex: (g.$3 * 1000 / total).round(),
                      child: Container(
                        margin: const EdgeInsets.only(right: 2),
                        color: civic.tone(g.$2),
                      ),
                    ),
              ]),
            ),
          ),
        ),
        Space.gapMd,
        Wrap(spacing: Space.lg, runSpacing: Space.sm, children: [
          for (final g in groups)
            Text.rich(
              TextSpan(children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                          color: civic.tone(g.$2), shape: BoxShape.circle)),
                ),
                TextSpan(text: '${g.$1} ${g.$3}'),
              ]),
              style: context.textStyles.labelMedium,
            ),
        ]),
      ]),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.children,
    required this.empty,
    required this.icon,
    this.action,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  final String empty;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: CivicCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Wraps the action under the title when both don't fit
            // (narrow screens, large text).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: Space.xs,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 20, color: context.colors.primary),
                  Space.gapSm,
                  Flexible(
                      child: Text(title, style: context.textStyles.titleSmall)),
                ]),
                if (action != null) action!,
              ],
            ),
            Space.gapSm,
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child:
                    Text(empty, style: TextStyle(color: context.civic.muted)),
              )
            else
              ...children,
          ]),
        ),
      );
}

/// List row that wraps its trailing action under the text on narrow widths.
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: Radii.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: LayoutBuilder(builder: (context, c) {
            final text =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle,
                  maxLines: adaptiveLines(context),
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.civic.muted)),
            ]);
            if (c.maxWidth < 380) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    Space.gapMd,
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [text, Space.gapSm, trailing]),
                    ),
                  ]);
            }
            return Row(children: [
              leading,
              Space.gapMd,
              Expanded(child: text),
              Space.gapSm,
              trailing,
            ]);
          }),
        ),
      );
}

class AdminQueueTab extends StatelessWidget {
  const AdminQueueTab({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => ComplaintListCubit(
          context.read<ComplaintRepository>(),
          sort: ComplaintSort.priority,
          statuses: const {
            ComplaintStatus.submitted,
            ComplaintStatus.underReview,
          },
        ),
        child: const ComplaintListView(
          heroScope: 'queue',
          tableOnWide: true,
          resultsLabel: 'reports',
          presets: [
            StatusPreset('New',
                {ComplaintStatus.submitted, ComplaintStatus.underReview}),
            StatusPreset('Verified', {ComplaintStatus.verified}),
            StatusPreset('In work', {
              ComplaintStatus.assigned,
              ComplaintStatus.inProgress,
              ComplaintStatus.reworkRequired,
            }),
            StatusPreset('Inspection', {ComplaintStatus.awaitingInspection}),
            StatusPreset('Closed', {
              ComplaintStatus.resolved,
              ComplaintStatus.rejected,
              ComplaintStatus.duplicate,
            }),
            StatusPreset('All', {}),
          ],
          emptyTitle: 'Queue is clear',
          emptyMessage: 'New citizen reports will appear here instantly.',
        ),
      );
}
