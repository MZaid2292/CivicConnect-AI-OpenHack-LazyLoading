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
import '../../auth/presentation/cubit/session_cubit.dart';
import '../domain/app_notification.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final actor = context.read<SessionCubit>().state.actor!;
    final repo = context.read<NotificationRepository>();
    return BlocProvider(
      create: (_) =>
          WatchCubit<List<AppNotification>>(() => repo.watchFor(actor.id)),
      child: BlocBuilder<WatchCubit<List<AppNotification>>,
          DataState<List<AppNotification>>>(
        builder: (context, state) {
          final unread = state.data?.where((n) => !n.read).length ?? 0;
          return Scaffold(
            appBar: CivicAppBar(
              title: 'Notifications',
              subtitle: unread == 0 ? 'All caught up' : '$unread unread',
              fallbackLocation: Routes.home,
              actions: [
                if (unread > 0)
                  CivicAppBarAction(
                    icon: Icons.done_all,
                    label: 'Mark all read',
                    onPressed: () => repo.markAllRead(actor.id),
                  ),
                Space.gapSm,
              ],
            ),
            body: switch (state.status) {
              LoadStatus.loading => const CivicLoadingState(),
              LoadStatus.failure => CivicErrorState(
                  message: state.error!,
                  onRetry:
                      context.read<WatchCubit<List<AppNotification>>>().retry),
              LoadStatus.ready when state.data!.isEmpty =>
                const CivicEmptyState(
                    icon: Icons.notifications_none,
                    title: 'All caught up',
                    message:
                        'Status changes on your reports and jobs show here.'),
              LoadStatus.ready => ListView.separated(
                  padding: pagePadding(context),
                  itemCount: state.data!.length,
                  separatorBuilder: (_, __) => Space.gapSm,
                  itemBuilder: (context, i) => ResponsiveCenter(
                    maxWidth: 760,
                    child: _NotificationTile(
                        notification: state.data![i], role: actor.role),
                  ),
                ),
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.role});
  final AppNotification notification;
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final icon = n.jobId != null
        ? Icons.construction
        : (n.title.contains('Resolved') || n.title.contains('resolved')
            ? Icons.check_circle_outline
            : Icons.notifications_active_outlined);
    return CivicCard(
      color: n.read
          ? null
          : context.colors.primaryContainer.withValues(alpha: 0.35),
      onTap: () {
        if (n.complaintId != null) {
          context.push(Routes.complaint(n.complaintId!));
        } else if (n.jobId != null && role != AppRole.citizen) {
          context.push(Routes.job(n.jobId!));
        }
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CivicIconBadge(
            icon: icon,
            color: n.read ? AppColors.slate : AppColors.civicBlue,
            size: 40),
        Space.gapMd,
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: context.textStyles.titleSmall),
            const SizedBox(height: 2),
            Text(n.body, style: context.textStyles.bodyMedium),
            const SizedBox(height: 4),
            Text(timeAgo(n.at),
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.civic.muted)),
          ]),
        ),
        if (!n.read)
          Semantics(
            label: 'Unread',
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6, left: Space.sm),
              decoration: BoxDecoration(
                  color: context.colors.primary, shape: BoxShape.circle),
            ),
          ),
      ]),
    );
  }
}
