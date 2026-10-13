import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/di/app_dependencies.dart';
import 'features/auth/presentation/cubit/session_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On web, keep the address bar in sync with pushed screens (e.g. a
  // complaint detail) so reloading or sharing the URL reopens that screen.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  // Supabase is initialised only when a key is supplied via
  // --dart-define-from-file=supabase.local.json. Repositories are still the
  // local ones until the Supabase adapters are switched on.
  final supabase = SupabaseConfig.fromEnvironment();
  if (supabase != null) {
    await Supabase.initialize(
        url: supabase.url, publishableKey: supabase.anonKey);
  }
  final preferences = await SharedPreferences.getInstance();
  final dependencies = AppDependencies(preferences);
  final sessionCubit = SessionCubit(dependencies.sessionRepository)
    ..restoreSession();
  runApp(BlocProvider.value(
      value: sessionCubit, child: CivicConnectApp(dependencies: dependencies)));
}
