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

class RoleHome extends StatelessWidget {
  const RoleHome({super.key});

  @override
  Widget build(BuildContext context) {
    final actor = context.select((SessionCubit c) => c.state.actor);
    if (actor == null) return const Scaffold(body: CivicLoadingState());
    final notifications = context.read<NotificationRepository>();
    return _PasswordRecoveryPrompt(
      child: BlocProvider(
        key: ValueKey(actor.id),
        create: (_) => WatchCubit<List<AppNotification>>(
            () => notifications.watchFor(actor.id)),
        child: switch (actor.role) {
          AppRole.citizen => const CitizenHome(),
          AppRole.municipalAdmin => const AdminHome(),
          AppRole.contractor => const ContractorHome(),
        },
      ),
    );
  }
}

class _PasswordRecoveryPrompt extends StatefulWidget {
  const _PasswordRecoveryPrompt({required this.child});
  final Widget child;

  @override
  State<_PasswordRecoveryPrompt> createState() =>
      _PasswordRecoveryPromptState();
}

class _PasswordRecoveryPromptState extends State<_PasswordRecoveryPrompt> {
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    if (context.read<SessionCubit>().state.recoveringPassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
    }
  }

  Future<void> _prompt() async {
    if (_prompting || !mounted) return;
    _prompting = true;
    final session = context.read<SessionCubit>();
    final password = await promptForText(context,
        title: 'Choose a new password',
        label: 'New password',
        confirmLabel: 'Save password',
        minLength: 8,
        obscure: true);
    _prompting = false;
    if (password == null || !mounted) return;
    try {
      await session.updatePassword(password);
      if (mounted) showMessage(context, 'Password updated.');
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<SessionCubit, SessionState>(
        listenWhen: (a, b) => !a.recoveringPassword && b.recoveringPassword,
        listener: (_, __) => _prompt(),
        child: widget.child,
      );
}
