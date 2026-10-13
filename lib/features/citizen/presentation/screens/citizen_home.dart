import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/models/app_role.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/greeting.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/complaint_repository.dart';
import '../../../complaints/presentation/cubit/complaint_list_cubit.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../../complaints/presentation/widgets/complaint_list_view.dart';
import '../../../shell/presentation/role_shell.dart';
import '../../../transparency/presentation/transparency_screen.dart';

class CitizenHome extends StatelessWidget {
  const CitizenHome({super.key});

  @override
  Widget build(BuildContext context) {
    final fab = FloatingActionButton.extended(
      heroTag: 'report',
      onPressed: () => context.push(Routes.newReport),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Report issue'),
    );
    return RoleShell(role: AppRole.citizen, tabs: [
      ShellTab(
        label: 'Home',
        title: 'CivicConnect',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        fab: fab,
        child: const CitizenFeedTab(),
      ),
      ShellTab(
        label: 'My reports',
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        fab: fab,
        child: const MyReportsTab(),
      ),
      const ShellTab(
        label: 'Transparency',
        icon: Icons.public_outlined,
        selectedIcon: Icons.public,
        child: TransparencyScreen(),
      ),
      const ShellTab(
        label: 'Profile',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        child: CitizenProfileTab(),
      ),
    ]);
  }
}

class CitizenFeedTab extends StatelessWidget {
  const CitizenFeedTab({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) =>
            ComplaintListCubit(context.read<ComplaintRepository>()),
        child: ComplaintListView(
          heroScope: 'feed',
          resultsLabel: 'reports near you',
          headerBuilder: (context, state) => _CitizenHeader(state: state),
        ),
      );
}

class _CitizenHeader extends StatelessWidget {
  const _CitizenHeader({required this.state});
  final ComplaintListState state;

  @override
  Widget build(BuildContext context) {
    final actor = context.read<SessionCubit>().state.actor!;
    final session = context.read<SessionCubit>().state;
    final city = session.live
        ? (session.profile?.municipalityName ?? 'Your municipality')
        : 'Ward 4 · ${context.read<AppConfig>().cityName}';
    final mine = state.all.where((c) => c.reporterId == actor.id);
    final open = mine.where((c) => c.status.isOpen).length;
    final resolved =
        mine.where((c) => c.status == ComplaintStatus.resolved).length;
    final supported =
        state.all.where((c) => c.supporterIds.contains(actor.id)).length;
    final firstName = actor.name.split(' ').first;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CivicHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.place_outlined,
                size: 16, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ),
          ]),
          Space.gapSm,
          TimeGreeting(
              name: firstName,
              style: context.textStyles.headlineSmall
                  ?.copyWith(color: Colors.white)),
          Space.gapXs,
          Text('Spotted something that needs fixing? It takes under a minute.',
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
          Space.gapLg,
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.navy,
            ),
            onPressed: () => context.push(Routes.newReport),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Report an issue'),
          ),
        ]),
      ),
      Space.gapLg,
      AdaptiveGrid(minTileWidth: 160, children: [
        CivicStatCard(
            label: 'My open reports',
            value: '$open',
            icon: Icons.pending_actions_outlined,
            color: AppColors.amber),
        CivicStatCard(
            label: 'Resolved for me',
            value: '$resolved',
            icon: Icons.check_circle_outline,
            color: AppColors.teal),
        CivicStatCard(
            label: 'Reports I support',
            value: '$supported',
            icon: Icons.thumb_up_alt_outlined,
            color: AppColors.indigo),
      ]),
      const CivicSectionHeader('Browse by category',
          subtitle: 'Tap to filter the feed'),
      SizedBox(
        // Grows with the user's text size so labels never clip.
        height: 64 + MediaQuery.textScalerOf(context).scale(56),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ComplaintCategory.values.length,
          separatorBuilder: (_, __) => Space.gapMd,
          itemBuilder: (context, i) {
            final cat = ComplaintCategory.values[i];
            final count = state.all
                .where((c) => c.category == cat && c.status.isOpen)
                .length;
            return _CategoryTile(
              category: cat,
              openCount: count,
              selected: state.category == cat,
              onTap: () => context
                  .read<ComplaintListCubit>()
                  .setCategory(state.category == cat ? null : cat),
            );
          },
        ),
      ),
      const CivicSectionHeader('Reports near you',
          icon: Icons.near_me_outlined),
    ]);
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.openCount,
    required this.selected,
    required this.onTap,
  });
  final ComplaintCategory category;
  final int openCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: '${category.label}, $openCount open',
        excludeSemantics: true,
        child: SizedBox(
          width: 132,
          child: CivicCard(
            onTap: onTap,
            flat: true,
            padding: const EdgeInsets.all(Space.md),
            color: selected ? context.colors.primaryContainer : null,
            borderColor: selected ? context.colors.primary : null,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(category.icon,
                  color: selected
                      ? context.colors.onPrimaryContainer
                      : context.colors.primary),
              const Spacer(),
              Text(category.shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelLarge),
              Text('$openCount open',
                  style: context.textStyles.labelSmall
                      ?.copyWith(color: context.civic.muted)),
            ]),
          ),
        ),
      );
}

class MyReportsTab extends StatelessWidget {
  const MyReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.read<SessionCubit>().state.actor!.id;
    return BlocProvider(
      create: (context) => ComplaintListCubit(
        context.read<ComplaintRepository>(),
        scope: (c) => c.reporterId == me,
      ),
      child: const ComplaintListView(
        heroScope: 'mine',
        resultsLabel: 'of your reports',
        presets: [
          StatusPreset('All', {}),
          StatusPreset('Drafts', {ComplaintStatus.draft}),
          StatusPreset('Active', {
            ComplaintStatus.submitted,
            ComplaintStatus.underReview,
            ComplaintStatus.verified,
            ComplaintStatus.assigned,
            ComplaintStatus.inProgress,
            ComplaintStatus.awaitingInspection,
            ComplaintStatus.reworkRequired,
          }),
          StatusPreset('Closed', {
            ComplaintStatus.resolved,
            ComplaintStatus.rejected,
            ComplaintStatus.duplicate,
          }),
        ],
        emptyTitle: 'You have not reported anything yet',
        emptyMessage: 'Tap "Report issue" to file your first civic report.',
      ),
    );
  }
}

class CitizenProfileTab extends StatelessWidget {
  const CitizenProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final actor = context.read<SessionCubit>().state.actor!;
    return BlocProvider(
      create: (context) =>
          ComplaintListCubit(context.read<ComplaintRepository>()),
      child: BlocBuilder<ComplaintListCubit, ComplaintListState>(
        builder: (context, state) {
          final mine = state.all.where((c) => c.reporterId == actor.id);
          final supported =
              state.all.where((c) => c.supporterIds.contains(actor.id));
          final resolved =
              mine.where((c) => c.status == ComplaintStatus.resolved);
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
                      child: Row(children: [
                        CivicAvatar(name: actor.name, radius: 32),
                        Space.gapLg,
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(actor.name,
                                    style: context.textStyles.titleLarge),
                                Text(
                                    context.isLiveBackend
                                        ? 'Citizen · ${context.read<SessionCubit>().state.profile?.municipalityName ?? 'No municipality linked'}'
                                        : 'Citizen · Ward 4',
                                    style: context.textStyles.bodyMedium
                                        ?.copyWith(color: context.civic.muted)),
                                Space.gapSm,
                                if (context.isLiveBackend)
                                  Pill(
                                      label: context
                                              .read<SessionCubit>()
                                              .state
                                              .profile
                                              ?.email ??
                                          '',
                                      color: AppColors.civicBlue,
                                      icon: Icons.mail_outline)
                                else
                                  const Pill(
                                      label: 'Demo profile',
                                      color: AppColors.amber,
                                      icon: Icons.science_outlined),
                              ]),
                        ),
                      ]),
                    ),
                    Space.gapLg,
                    AdaptiveGrid(minTileWidth: 170, children: [
                      CivicStatCard(
                          label: 'Reports filed',
                          value:
                              '${mine.where((c) => c.status.isPublic).length}',
                          icon: Icons.outbox_outlined),
                      CivicStatCard(
                          label: 'Resolved',
                          value: '${resolved.length}',
                          icon: Icons.check_circle_outline,
                          color: AppColors.teal),
                      CivicStatCard(
                          label: 'Supported',
                          value: '${supported.length}',
                          icon: Icons.thumb_up_alt_outlined,
                          color: AppColors.indigo),
                    ]),
                    const CivicSectionHeader('Account & app'),
                    CivicCard(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Column(children: [
                        ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: const Text('Notifications'),
                          subtitle:
                              const Text('Status changes on your reports'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.notifications),
                        ),
                        ListTile(
                          leading: Icon(dark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined),
                          title: const Text('Appearance'),
                          subtitle: Text(
                              'Follows your device setting · currently ${dark ? 'Dark' : 'Light'}'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.public),
                          title: const Text('Public transparency'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.transparency),
                        ),
                        const Divider(indent: Space.lg, endIndent: Space.lg),
                        ListTile(
                          leading:
                              Icon(Icons.logout, color: context.colors.error),
                          title: Text(
                              context.isLiveBackend
                                  ? 'Log out'
                                  : 'Switch role / log out',
                              style: TextStyle(color: context.colors.error)),
                          subtitle: Text(context.isLiveBackend
                              ? 'Signs you out on this device'
                              : 'Clears the saved demo role on this device'),
                          onTap: () => context.read<SessionCubit>().logout(),
                        ),
                      ]),
                    ),
                  ]),
            ),
          );
        },
      ),
    );
  }
}
