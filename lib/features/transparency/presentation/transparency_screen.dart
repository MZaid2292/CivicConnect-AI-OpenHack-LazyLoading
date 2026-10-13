import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/app_role.dart';
import '../../../core/presentation/watch_cubit.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/civic_widgets.dart';
import '../../complaints/domain/complaint.dart';
import '../../complaints/domain/complaint_repository.dart';
import '../../complaints/presentation/cubit/complaint_list_cubit.dart';
import '../../complaints/presentation/widgets/badges.dart';

/// Public accountability view: city-wide stats and a feed of every status
/// change, newest first.
class TransparencyScreen extends StatelessWidget {
  const TransparencyScreen({super.key, this.standalone = false});
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final body = BlocProvider(
      create: (context) =>
          ComplaintListCubit(context.read<ComplaintRepository>()),
      child: BlocBuilder<ComplaintListCubit, ComplaintListState>(
        builder: (context, state) {
          if (state.status == LoadStatus.loading) {
            return const CivicLoadingState();
          }
          if (state.status == LoadStatus.failure) {
            return CivicErrorState(
                message: state.error ?? 'Could not load data.',
                onRetry: context.read<ComplaintListCubit>().retry);
          }
          final all = state.all;
          final resolved =
              all.where((c) => c.status == ComplaintStatus.resolved).toList();
          final open = all.where((c) => c.status.isOpen).length;
          final durations = [
            for (final c in resolved)
              c.timeline.last.at.difference(c.createdAt).inHours / 24,
          ];
          final avgDays = durations.isEmpty
              ? null
              : durations.reduce((a, b) => a + b) / durations.length;
          final ratings = [
            for (final c in resolved)
              if (c.feedback != null) c.feedback!.rating
          ];
          final events = [
            for (final c in all)
              for (final e in c.timeline) (c, e),
          ]..sort((a, b) => b.$2.at.compareTo(a.$2.at));

          return SingleChildScrollView(
            padding: pagePadding(context),
            child: ResponsiveCenter(
              maxWidth: 960,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CivicHeroCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Public accountability',
                                style: context.textStyles.headlineSmall
                                    ?.copyWith(color: Colors.white)),
                            Space.gapXs,
                            Text(
                                'Every status change is logged with who made '
                                'it and when — visible to all residents.',
                                style: context.textStyles.bodyMedium?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.85))),
                          ]),
                    ),
                    Space.gapLg,
                    AdaptiveGrid(minTileWidth: 190, children: [
                      CivicStatCard(
                          label: 'Reports filed',
                          value: '${all.length}',
                          icon: Icons.outbox_outlined),
                      CivicStatCard(
                          label: 'Open now',
                          value: '$open',
                          icon: Icons.pending_actions_outlined,
                          color: AppColors.amber),
                      CivicStatCard(
                          label: 'Resolved',
                          value: '${resolved.length}',
                          icon: Icons.check_circle_outline,
                          color: AppColors.teal),
                      CivicStatCard(
                          label: 'Avg. days to resolve',
                          value: avgDays == null
                              ? '—'
                              : avgDays.toStringAsFixed(1),
                          icon: Icons.timer_outlined,
                          color: AppColors.indigo,
                          caption: ratings.isEmpty
                              ? null
                              : '★ ${(ratings.reduce((a, b) => a + b) / ratings.length).toStringAsFixed(1)} citizen rating'),
                    ]),
                    const CivicSectionHeader('Activity log',
                        icon: Icons.history,
                        subtitle: 'Latest 40 status changes'),
                    if (events.isEmpty)
                      const CivicEmptyState(
                          icon: Icons.history,
                          title: 'No activity yet',
                          message: 'Status changes will appear here.')
                    else
                      CivicCard(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Column(children: [
                          for (final (c, e) in events.take(40))
                            InkWell(
                              onTap: () => context.push(Routes.complaint(c.id)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: Space.lg, vertical: Space.md),
                                child: Row(children: [
                                  CivicIconBadge(
                                      icon: e.status.icon,
                                      color: e.status.color,
                                      size: 36),
                                  Space.gapMd,
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${c.id} · ${c.title}',
                                              maxLines: adaptiveLines(context),
                                              overflow: TextOverflow.ellipsis,
                                              style: context
                                                  .textStyles.bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600)),
                                          Text(
                                              '${e.status.label} by ${e.actorRole.label} · ${timeAgo(e.at)}',
                                              style: context
                                                  .textStyles.bodySmall
                                                  ?.copyWith(
                                                      color:
                                                          context.civic.muted)),
                                        ]),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: context.civic.subtle),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                  ]),
            ),
          );
        },
      ),
    );
    return standalone
        ? Scaffold(
            appBar: const CivicAppBar(
                title: 'Transparency',
                subtitle: 'Public activity log',
                fallbackLocation: Routes.home),
            body: body)
        : body;
  }
}
