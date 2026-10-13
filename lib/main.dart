import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/di/app_dependencies.dart';
import 'features/auth/presentation/cubit/session_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On web, keep the address bar in sync with pushed screens (e.g. a
  // complaint detail) so reloading or sharing the URL reopens that screen.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final preferences = await SharedPreferences.getInstance();
  final dependencies = AppDependencies(preferences);
  final sessionCubit = SessionCubit(dependencies.sessionRepository)
    ..restoreSession();
  runApp(BlocProvider.value(
      value: sessionCubit, child: CivicConnectApp(dependencies: dependencies)));
}
