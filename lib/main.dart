import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';
import 'core/di/app_dependencies.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/civic_widgets.dart';
import 'features/auth/presentation/cubit/session_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoRouter.optionURLReflectsImperativeAPIs = true;

  SupabaseConfig? supabase;
  try {
    supabase = SupabaseConfig.fromEnvironment();
  } on StateError catch (e) {
    runApp(_ConfigurationError(e.message));
    return;
  }
  if (supabase == null && kReleaseMode) {
    runApp(const _ConfigurationError(
        'This build has no backend configuration. Build it with '
        '--dart-define-from-file=supabase.local.json.'));
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  final AppDependencies dependencies;
  if (supabase != null) {
    await Supabase.initialize(
        url: supabase.url, publishableKey: supabase.anonKey);
    dependencies = AppDependencies.live(preferences, Supabase.instance.client);
  } else {
    dependencies = AppDependencies(preferences);
  }
  final sessionCubit = SessionCubit(dependencies.sessionRepository,
      auth: dependencies.authRepository)
    ..restoreSession();
  runApp(BlocProvider.value(
      value: sessionCubit, child: CivicConnectApp(dependencies: dependencies)));
}

class _ConfigurationError extends StatelessWidget {
  const _ConfigurationError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: Scaffold(
          body: CivicErrorState(message: message),
        ),
      );
}
