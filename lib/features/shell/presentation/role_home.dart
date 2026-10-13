import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/app_role.dart';
import '../../../core/presentation/watch_cubit.dart';
import '../../../core/widgets/civic_widgets.dart';
import '../../admin/presentation/screens/admin_home.dart';
import '../../auth/presentation/cubit/session_cubit.dart';
import '../../citizen/presentation/screens/citizen_home.dart';
import '../../contractor/presentation/screens/contractor_home.dart';
import '../../notifications/domain/app_notification.dart';

/// Picks the dashboard for the active demo role.
class RoleHome extends StatelessWidget {
  const RoleHome({super.key});

  @override
  Widget build(BuildContext context) {
    final actor = context.select((SessionCubit c) => c.state.actor);
    if (actor == null) return const Scaffold(body: CivicLoadingState());
    final notifications = context.read<NotificationRepository>();
    return BlocProvider(
      key: ValueKey(actor.id),
      create: (_) => WatchCubit<List<AppNotification>>(
          () => notifications.watchFor(actor.id)),
      child: switch (actor.role) {
        AppRole.citizen => const CitizenHome(),
        AppRole.municipalAdmin => const AdminHome(),
        AppRole.contractor => const ContractorHome(),
      },
    );
  }
}
