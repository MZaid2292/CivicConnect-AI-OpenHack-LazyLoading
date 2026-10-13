import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/cubit/session_cubit.dart';
import '../../features/auth/presentation/screens/demo_login_screen.dart';
import '../../features/auth/presentation/screens/role_selection_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/admin/presentation/screens/inspection_screen.dart';
import '../../features/citizen/presentation/screens/create_complaint_screen.dart';
import '../../features/complaints/presentation/screens/complaint_detail_screen.dart';
import '../../features/jobs/presentation/screens/job_detail_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/shell/presentation/role_home.dart';
import '../../features/transparency/presentation/transparency_screen.dart';
import '../models/app_role.dart';
import '../widgets/civic_widgets.dart';

class Routes {
  const Routes._();
  static const loading = '/loading';
  static const welcome = '/welcome';
  static const login = '/login';
  static const role = '/role';
  static const home = '/home';
  static const newReport = '/report/new';
  static String editDraft(String id) => '/report/edit/$id';
  static String complaint(String id) => '/complaint/$id';
  static String job(String id) => '/job/$id';
  static String inspect(String jobId) => '/inspect/$jobId';
  static const notifications = '/notifications';
  static const transparency = '/transparency';
}

const _authRoutes = {Routes.welcome, Routes.login, Routes.role};

/// Client-side guard for demo navigation only. Real authorisation must be
/// enforced server-side (Supabase RLS) in the integration phase.
///
/// While the session is restoring, the requested location is carried in
/// `/loading?from=…` so a deep link (e.g. a browser reload of
/// `/complaint/CMP-1001`) opens that screen once the role is known.
String? sessionRedirect(SessionState session, Uri uri) {
  final location = uri.path;
  if (session.loading) {
    if (location == Routes.loading) return null;
    final keep = location != '/' && !_authRoutes.contains(location);
    return keep
        ? Uri(path: Routes.loading, queryParameters: {'from': uri.toString()})
            .toString()
        : Routes.loading;
  }
  final role = session.role;
  if (role == null) {
    if (_authRoutes.contains(location)) return null;
    return session.onboardingSeen ? Routes.role : Routes.welcome;
  }
  if (location == Routes.loading) {
    final from = uri.queryParameters['from'];
    if (from != null && from.startsWith('/')) {
      final target = Uri.parse(from);
      if (target.path != Routes.loading) {
        return sessionRedirect(session, target) ?? from;
      }
    }
    return Routes.home;
  }
  if (_authRoutes.contains(location) || location == '/') {
    return Routes.home;
  }
  if (location.startsWith('/report') && role != AppRole.citizen) {
    return Routes.home;
  }
  if (location.startsWith('/inspect') && role != AppRole.municipalAdmin) {
    return Routes.home;
  }
  if (location.startsWith('/job') && role == AppRole.citizen) {
    return Routes.home;
  }
  return null;
}

GoRouter buildAppRouter(SessionCubit sessionCubit) => GoRouter(
      initialLocation: '/',
      refreshListenable: _SessionChangeNotifier(sessionCubit.stream),
      redirect: (context, state) =>
          sessionRedirect(sessionCubit.state, state.uri),
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: CivicEmptyState(
          icon: Icons.explore_off_outlined,
          title: 'Page not found',
          message: 'That screen does not exist.',
          action: FilledButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Go home')),
        ),
      ),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const _Splash()),
        GoRoute(path: Routes.loading, builder: (_, __) => const _Splash()),
        GoRoute(
            path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
        GoRoute(
            path: Routes.login, builder: (_, __) => const DemoLoginScreen()),
        GoRoute(
            path: Routes.role, builder: (_, __) => const RoleSelectionScreen()),
        GoRoute(path: Routes.home, builder: (_, __) => const RoleHome()),
        GoRoute(
            path: Routes.newReport,
            builder: (_, __) => const CreateComplaintScreen()),
        GoRoute(
            path: '/report/edit/:id',
            builder: (_, s) =>
                CreateComplaintScreen(draftId: s.pathParameters['id'])),
        GoRoute(
            path: '/complaint/:id',
            builder: (_, s) => ComplaintDetailScreen(
                complaintId: s.pathParameters['id']!,
                heroTag: s.extra is String ? s.extra as String : null)),
        GoRoute(
            path: '/job/:id',
            builder: (_, s) => JobDetailScreen(jobId: s.pathParameters['id']!)),
        GoRoute(
            path: '/inspect/:id',
            builder: (_, s) =>
                InspectionScreen(jobId: s.pathParameters['id']!)),
        GoRoute(
            path: Routes.notifications,
            builder: (_, __) => const NotificationsScreen()),
        GoRoute(
            path: Routes.transparency,
            builder: (_, __) => const TransparencyScreen(standalone: true)),
      ],
    );

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: CivicLoadingState(label: 'Starting CivicConnect…'));
}

class _SessionChangeNotifier extends ChangeNotifier {
  _SessionChangeNotifier(Stream<SessionState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
