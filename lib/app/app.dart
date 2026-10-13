import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/di/app_dependencies.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/cubit/session_cubit.dart';

class CivicConnectApp extends StatefulWidget {
  const CivicConnectApp({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<CivicConnectApp> createState() => _CivicConnectAppState();
}

class _CivicConnectAppState extends State<CivicConnectApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildAppRouter(context.read<SessionCubit>());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dependencies;
    // One instance of each repository/service shared by every role and screen.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: d),
        RepositoryProvider.value(value: d.config),
        RepositoryProvider.value(value: d.mode),
        RepositoryProvider.value(value: d.complaintRepository),
        RepositoryProvider.value(value: d.jobRepository),
        RepositoryProvider.value(value: d.contractorRepository),
        RepositoryProvider.value(value: d.notificationRepository),
        RepositoryProvider.value(value: d.priorityRulesRepository),
        RepositoryProvider.value(value: d.complaintService),
        RepositoryProvider.value(value: d.jobService),
        RepositoryProvider.value(value: d.locationService),
        RepositoryProvider.value(value: d.mediaPicker),
      ],
      child: MaterialApp.router(
        title: 'CivicConnect AI',
        debugShowCheckedModeBanner: false,
        // Follows the OS appearance, including live changes while running.
        // Deliberately not stored in SharedPreferences.
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        routerConfig: _router,
      ),
    );
  }
}
