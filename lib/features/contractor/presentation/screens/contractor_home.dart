import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/models/app_role.dart';
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
import '../../../jobs/domain/job_repositories.dart';
import '../../../jobs/domain/work_job.dart';
import '../../../jobs/presentation/cubit/job_list_cubits.dart';
import '../../../jobs/presentation/widgets/job_card.dart';
import '../../../shell/presentation/role_shell.dart';

class ContractorHome extends StatelessWidget {
  const ContractorHome({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider(
              create: (_) => JobsCubit(context.read<JobRepository>().watchAll)),
          BlocProvider(
              create: (_) => ContractorsCubit(
                  context.read<ContractorRepository>().watchAll)),
        ],
        child: const RoleShell(role: AppRole.contractor, tabs: [
          ShellTab(
            label: 'Dashboard',
            icon: Icons.space_dashboard_outlined,
            selectedIcon: Icons.space_dashboard,
            child: _ContractorDashboard(),
          ),
          ShellTab(
            label: 'Available',
            title: 'Open tenders',
            icon: Icons.gavel_outlined,
            selectedIcon: Icons.gavel,
            child: _AvailableJobs(),
          ),
          ShellTab(
            label: 'My jobs',
            title: 'Assigned projects',
            icon: Icons.construction_outlined,
            selectedIcon: Icons.construction,
            child: _MyJobs(),
          ),
          ShellTab(
            label: 'Profile',
            title: 'Company profile',
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            child: _ContractorProfile(),
          ),
        ]),
      );
}

/// Shared loading/error handling for the contractor tabs.
class _JobsScope extends StatelessWidget {
  const _JobsScope({required this.builder});
  final Widget Function(BuildContext, List<WorkJob>, Contractor?, String me)
      builder;

  @override
  Widget build(BuildContext context) {
    final me = context.read<SessionCubit>().state.actor!.id;
    final jobs = context.watch<JobsCubit>().state;
    final contractors = context.watch<ContractorsCubit>().state;
    if (jobs.status == LoadStatus.loading) return const CivicLoadingState();
    if (jobs.status == LoadStatus.failure) {
      return CivicErrorState(
          message: jobs.error!, onRetry: context.read<JobsCubit>().retry);
    }
    final profile = contractors.data?.where((c) => c.id == me).firstOrNull;
    return builder(context, jobs.data!, profile, me);
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.color});
  final double rating;
  static const size = 18.0;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.civic.tone(AppColors.amber);
    return Semantics(
      label: '${rating.toStringAsFixed(1)} out of 5 stars',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(
              rating >= i
                  ? Icons.star
                  : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
              size: size,
              color: c),
      ]),
    );
  }
}

class _ContractorDashboard extends StatelessWidget {
  const _ContractorDashboard();

  @override
  Widget build(BuildContext context) => _JobsScope(
        builder: (context, jobs, profile, me) {
          final mine = jobs.where((j) => j.contractorId == me).toList();
          final active = mine.where((j) => j.status.isActive).toList();
          final todo = mine
              .where((j) =>
                  j.status == JobStatus.awarded ||
                  j.status == JobStatus.inProgress ||
                  j.status == JobStatus.reworkRequested)
              .toList();
          final open = jobs.where(
              (j) => j.status == JobStatus.openForBids && !j.hasBidFrom(me));
          final goTo = ShellScope.maybeOf(context)?.goToTab;
          final rating = profile?.averageRating;

          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CivicHeroCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hello, ${profile?.name ?? 'contractor'}',
                                style: context.textStyles.headlineSmall
                                    ?.copyWith(color: Colors.white)),
                            Space.gapSm,
                            Wrap(
                                spacing: Space.md,
                                runSpacing: Space.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (rating != null)
                                    _Stars(
                                        rating: rating,
                                        color: const Color(0xFFFCD34D)),
                                  Text(
                                      rating == null
                                          ? 'No citizen ratings yet'
                                          : '${rating.toStringAsFixed(1)} · ${profile!.ratingCount} citizen ratings',
                                      style: context.textStyles.bodyMedium
                                          ?.copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.85))),
                                ]),
                            Space.gapLg,
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.navy),
                              onPressed: () => goTo?.call(1),
                              icon: const Icon(Icons.gavel_outlined),
                              label: Text('Browse ${open.length} open tenders'),
                            ),
                          ]),
                    ),
                    if (profile != null && !profile.canReceiveWork) ...[
                      Space.gapMd,
                      InfoBanner(
                          color: AppColors.amber,
                          message: 'Your account is '
                              '${profile.status.label.toLowerCase()}. You '
                              'can browse but not bid until approved.'),
                    ],
                    Space.gapLg,
                    AdaptiveGrid(minTileWidth: 200, children: [
                      CivicStatCard(
                          label: 'Active jobs',
                          value: '${active.length}',
                          icon: Icons.construction,
                          color: AppColors.amber,
                          onTap: () => goTo?.call(2)),
                      CivicStatCard(
                          label: 'Open tenders',
                          value: '${open.length}',
                          icon: Icons.gavel,
                          onTap: () => goTo?.call(1)),
                      CivicStatCard(
                          label: 'Completed',
                          value: '${profile?.completedJobs ?? 0}',
                          icon: Icons.task_alt,
                          color: AppColors.teal),
                      CivicStatCard(
                          label: 'Rating',
                          value: rating == null
                              ? '—'
                              : '★ ${rating.toStringAsFixed(1)}',
                          icon: Icons.star_outline,
                          color: AppColors.amber,
                          caption:
                              '${profile?.ratingCount ?? 0} citizen ratings'),
                    ]),
                    LayoutBuilder(builder: (context, c) {
                      final next = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CivicSectionHeader('Next actions',
                                icon: Icons.checklist),
                            if (todo.isEmpty)
                              CivicCard(
                                  child: Text(
                                      'Nothing pending. Check open tenders.',
                                      style: TextStyle(
                                          color: context.civic.muted))),
                            for (final j in todo)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: Space.md),
                                child: JobCard(
                                  job: j,
                                  highlight: switch (j.status) {
                                    JobStatus.awarded =>
                                      'Start work & add before photos',
                                    JobStatus.reworkRequested =>
                                      'Rework requested',
                                    _ => 'Log progress / request inspection',
                                  },
                                  onTap: () => context.push(Routes.job(j.id)),
                                ),
                              ),
                          ]);
                      final money = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CivicSectionHeader('Earnings',
                                icon: Icons.account_balance_wallet_outlined),
                            _EarningsCard(jobs: mine),
                          ]);
                      if (c.maxWidth < 840) {
                        return Column(children: [next, money]);
                      }
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: next),
                            Space.gapXl,
                            Expanded(flex: 2, child: money),
                          ]);
                    }),
                  ]),
            ),
          );
        },
      );
}

/// Mock earnings ledger derived from job payment states.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.jobs});
  final List<WorkJob> jobs;

  @override
  Widget build(BuildContext context) {
    final released = jobs
        .where((j) => j.paymentStatus == PaymentStatus.releasedSimulated)
        .toList();
    final held = jobs
        .where((j) => j.paymentStatus == PaymentStatus.heldSimulated)
        .toList();
    int sum(List<WorkJob> l) => l.fold(0, (s, j) => s + (j.awardedAmount ?? 0));
    final civic = context.civic;
    return CivicCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child:
                  Text('Payment ledger', style: context.textStyles.titleSmall)),
          const Flexible(
              child: Pill(label: 'SIMULATION', color: AppColors.amber)),
        ]),
        Space.gapLg,
        Row(children: [
          Expanded(
              child: _Metric(
                  label: 'Released',
                  value: formatAmount(sum(released)),
                  color: AppColors.teal)),
          Space.gapMd,
          Expanded(
              child: _Metric(
                  label: 'Pending inspection',
                  value: formatAmount(sum(held)),
                  color: AppColors.amber)),
        ]),
        const Divider(height: Space.xl),
        if (released.isEmpty && held.isEmpty)
          Text('No payments yet.', style: TextStyle(color: civic.muted)),
        for (final j in [...released, ...held])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${j.id} · ${j.title}',
                          maxLines: adaptiveLines(context),
                          overflow: TextOverflow.ellipsis),
                      Text(formatAmount(j.awardedAmount ?? 0),
                          style: context.textStyles.labelLarge),
                    ]),
              ),
              Space.gapSm,
              Flexible(
                child: Pill(
                    label: j.paymentStatus.label,
                    color: j.paymentStatus == PaymentStatus.releasedSimulated
                        ? AppColors.teal
                        : AppColors.slate),
              ),
            ]),
          ),
        Space.gapSm,
        Text(
            'Ledger is illustrative only. No bank transfers or payment '
            'gateways are connected.',
            style: context.textStyles.bodySmall?.copyWith(color: civic.muted)),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
            color: context.civic.tint(color), borderRadius: Radii.brMd),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: context.textStyles.titleLarge
                    ?.copyWith(color: context.civic.tone(color))),
          ),
          Text(label,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.civic.muted)),
        ]),
      );
}

class _AvailableJobs extends StatelessWidget {
  const _AvailableJobs();

  @override
  Widget build(BuildContext context) => _JobsScope(
        builder: (context, jobs, profile, me) {
          final open =
              jobs.where((j) => j.status == JobStatus.openForBids).toList();
          if (open.isEmpty) {
            return const CivicEmptyState(
                icon: Icons.gavel_outlined,
                title: 'No open tenders',
                message: 'New municipal tenders appear here as soon as they '
                    'are published.');
          }
          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const InfoBanner(
                        icon: Icons.lightbulb_outline,
                        message: 'Bids are compared by the municipality on '
                            'price, timeline and your citizen rating.'),
                    Space.gapLg,
                    AdaptiveGrid(minTileWidth: 360, children: [
                      for (final j in open)
                        JobCard(
                          job: j,
                          highlight: j.hasBidFrom(me)
                              ? 'You bid on this'
                              : 'Tap to view scope and bid',
                          onTap: () => context.push(Routes.job(j.id)),
                        ),
                    ]),
                  ]),
            ),
          );
        },
      );
}

class _MyJobs extends StatefulWidget {
  const _MyJobs();
  @override
  State<_MyJobs> createState() => _MyJobsState();
}

class _MyJobsState extends State<_MyJobs> {
  bool _active = true;

  @override
  Widget build(BuildContext context) => _JobsScope(
        builder: (context, jobs, profile, me) {
          final mine = jobs
              .where(
                  (j) => j.contractorId == me && j.status.isActive == _active)
              .toList();
          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                              value: true,
                              icon: Icon(Icons.construction),
                              label: Text('Active')),
                          ButtonSegment(
                              value: false,
                              icon: Icon(Icons.task_alt),
                              label: Text('Completed')),
                        ],
                        selected: {_active},
                        onSelectionChanged: (s) =>
                            setState(() => _active = s.first),
                      ),
                    ),
                    Space.gapLg,
                    if (mine.isEmpty)
                      CivicEmptyState(
                          icon: Icons.construction_outlined,
                          title: _active
                              ? 'No active jobs'
                              : 'No completed jobs yet',
                          message: _active
                              ? 'Win a tender or wait for a direct assignment.'
                              : 'Accepted jobs will be listed here.')
                    else
                      AdaptiveGrid(minTileWidth: 360, children: [
                        for (final j in mine)
                          JobCard(
                              job: j,
                              onTap: () => context.push(Routes.job(j.id))),
                      ]),
                  ]),
            ),
          );
        },
      );
}

class _ContractorProfile extends StatelessWidget {
  const _ContractorProfile();

  @override
  Widget build(BuildContext context) => _JobsScope(
        builder: (context, jobs, profile, me) {
          if (profile == null) {
            return CivicEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Profile not found',
                message: context.isLiveBackend
                    ? 'No contractor profile is linked to this account.'
                    : 'This demo contractor is not registered.');
          }
          final dark = context.civic.isDark;
          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              maxWidth: 760,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CivicCard(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CivicAvatar(name: profile.name, radius: 30),
                              Space.gapLg,
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(profile.name,
                                          style: context.textStyles.titleLarge),
                                      Text(
                                          context.isLiveBackend
                                              ? 'ID ${profile.registrationNo}'
                                              : 'Reg. ${profile.registrationNo} (mock)',
                                          style: context.textStyles.bodySmall
                                              ?.copyWith(
                                                  color: context.civic.muted)),
                                      Space.gapSm,
                                      Pill(
                                          label: profile.status.label,
                                          color: AppColors.teal,
                                          icon: Icons.verified_user_outlined),
                                    ]),
                              ),
                            ]),
                            Space.gapLg,
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final s in profile.specialties)
                                Pill(
                                    label: s.label,
                                    color: AppColors.civicBlue,
                                    icon: s.icon),
                            ]),
                          ]),
                    ),
                    const CivicSectionHeader('Public performance',
                        icon: Icons.star_outline),
                    CivicCard(
                      // Wrap: the rating moves above the details when large
                      // text leaves no room side by side.
                      child: Wrap(
                          spacing: Space.lg,
                          runSpacing: Space.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                                profile.averageRating == null
                                    ? '—'
                                    : profile.averageRating!.toStringAsFixed(1),
                                style: context.textStyles.displaySmall),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Stars(rating: profile.averageRating ?? 0),
                                    Text(
                                        '${profile.ratingCount} citizen ratings · '
                                        '${profile.completedJobs} jobs completed',
                                        style: context.textStyles.bodySmall
                                            ?.copyWith(
                                                color: context.civic.muted)),
                                    Text(
                                        'Member since ${formatDate(profile.joinedAt)}',
                                        style: context.textStyles.bodySmall
                                            ?.copyWith(
                                                color: context.civic.muted)),
                                  ]),
                            ),
                          ]),
                    ),
                    const CivicSectionHeader('Account & app'),
                    CivicCard(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Column(children: [
                        ListTile(
                          leading: Icon(dark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined),
                          title: const Text('Appearance'),
                          subtitle: Text(
                              'Follows your device setting · currently ${dark ? 'Dark' : 'Light'}'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: const Text('Notifications'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.notifications),
                        ),
                        ListTile(
                          leading:
                              Icon(Icons.logout, color: context.colors.error),
                          title: Text(
                              context.isLiveBackend
                                  ? 'Log out'
                                  : 'Switch role / log out',
                              style: TextStyle(color: context.colors.error)),
                          onTap: () => context.read<SessionCubit>().logout(),
                        ),
                      ]),
                    ),
                  ]),
            ),
          );
        },
      );
}
