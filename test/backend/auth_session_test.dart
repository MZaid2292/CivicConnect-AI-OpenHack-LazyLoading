import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/router/app_router.dart';
import 'package:civicconnect_ai/features/auth/data/local_session_repository.dart';
import 'package:civicconnect_ai/features/auth/domain/auth_repository.dart';
import 'package:civicconnect_ai/features/auth/presentation/cubit/session_cubit.dart';
import 'package:civicconnect_ai/features/jobs/domain/contractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';

const contractorProfile = UserProfile(
  userId: 'owner-uuid',
  email: 'works@example.com',
  displayName: 'Metro Works',
  dbRole: 'contractor',
  role: AppRole.contractor,
  municipalityId: 'muni-1',
  contractorId: 'contractor-uuid',
  contractorStatus: ContractorStatus.approved,
);

Future<(SessionCubit, FakeAuthRepository)> session(
    {UserProfile? persisted, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final auth = FakeAuthRepository(persisted: persisted, accounts: {
    'sana@example.com': ('correct-horse', citizenProfile()),
  });
  final cubit = SessionCubit(
      LocalSessionRepository(await SharedPreferences.getInstance()),
      auth: auth);
  await cubit.restoreSession();
  return (cubit, auth);
}

void main() {
  group('live session', () {
    test('a persisted session is restored with the trusted profile', () async {
      final (cubit, _) = await session(persisted: citizenProfile());
      expect(cubit.state.live, isTrue);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.role, AppRole.citizen);
      expect(cubit.state.actor!.id, 'user-citizen-1');
      expect(cubit.state.actor!.name, 'Sana Iqbal');
    });

    test('no session means signed out', () async {
      final (cubit, _) = await session();
      expect(cubit.state.actor, isNull);
      expect(cubit.state.role, isNull);
    });

    test('a saved demo role grants nothing in live mode', () async {
      final (cubit, _) = await session(prefs: {'demo_role': 'municipalAdmin'});
      expect(cubit.state.actor, isNull,
          reason: 'SharedPreferences is never proof of identity');
      await expectLater(
          cubit.enterDemo(AppRole.municipalAdmin), throwsA(anything));
      expect(cubit.state.role, isNull);
    });

    test('sign-in failures leave the user signed out', () async {
      final (cubit, _) = await session();
      await expectLater(cubit.signIn('sana@example.com', 'wrong'),
          throwsA(predicate((e) => '$e' == 'Incorrect email or password.')));
      expect(cubit.state.actor, isNull);
    });

    test('sign-in, then sign-out clears the session', () async {
      final (cubit, auth) = await session();
      await cubit.signIn('sana@example.com', 'correct-horse');
      expect(cubit.state.actor!.role, AppRole.citizen);
      await cubit.logout();
      expect(cubit.state.actor, isNull);
      expect(auth.currentProfile, isNull);
      expect(cubit.state.onboardingSeen, isTrue);
    });

    test('sign-up creates a citizen, or waits for email confirmation',
        () async {
      final (cubit, auth) = await session();
      auth.confirmEmailOnSignUp = true;
      expect(
          await cubit.signUp('New', 'new@example.com', 'password1'), isFalse);
      expect(cubit.state.actor, isNull);
      auth.confirmEmailOnSignUp = false;
      expect(await cubit.signUp('New', 'new@example.com', 'password1'), isTrue);
      expect(cubit.state.role, AppRole.citizen);
    });

    test('contractor accounts act as their contractor record', () async {
      final (cubit, _) = await session(persisted: contractorProfile);
      expect(cubit.state.actor!.id, 'contractor-uuid');
      expect(cubit.state.role, AppRole.contractor);
    });

    test('password recovery asks for a new password', () async {
      final (cubit, auth) = await session(persisted: citizenProfile());
      auth.emit(AuthEvent.passwordRecovery);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.recoveringPassword, isTrue);
      await cubit.updatePassword('new-password-1');
      expect(auth.updatedPassword, 'new-password-1');
      expect(cubit.state.recoveringPassword, isFalse);
    });

    test('a server-side sign-out event signs the app out', () async {
      final (cubit, auth) = await session(persisted: citizenProfile());
      auth.emit(AuthEvent.signedOut);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.actor, isNull);
    });
  });

  group('routing guards', () {
    const signedOut =
        SessionState(live: true, loading: false, onboardingSeen: true);
    final citizen = SessionState(
        live: true,
        loading: false,
        onboardingSeen: true,
        profile: citizenProfile(),
        role: AppRole.citizen);

    String? go(SessionState s, String location) =>
        sessionRedirect(s, Uri.parse(location));

    test('signed-out deep links go to sign-in and keep the target', () {
      expect(go(signedOut, '/complaint/CMP-1'),
          '/login?from=%2Fcomplaint%2FCMP-1');
      expect(go(signedOut, '/role'), '/login',
          reason: 'demo role selector is unreachable with real accounts');
      expect(go(signedOut, '/welcome'), '/login');
      expect(go(signedOut, '/login'), isNull);
    });

    test('a session restore keeps the deep link through sign-in', () {
      const loading = SessionState(live: true);
      expect(go(loading, '/complaint/CMP-1'),
          '/loading?from=%2Fcomplaint%2FCMP-1');
      expect(go(signedOut, '/loading?from=%2Fcomplaint%2FCMP-1'),
          '/login?from=%2Fcomplaint%2FCMP-1');
    });

    test('after sign-in the original target opens, subject to role guards', () {
      expect(
          go(citizen, '/login?from=%2Fcomplaint%2FCMP-1'), '/complaint/CMP-1');
      expect(go(citizen, '/login?from=%2Finspect%2FJOB-1'), '/home',
          reason: 'citizens cannot open admin inspection');
      expect(go(citizen, '/login'), '/home');
      expect(go(citizen, '/job/JOB-1'), '/home');
    });

    test('local preview routing is unchanged', () {
      const demo = SessionState(loading: false, onboardingSeen: true);
      expect(go(demo, '/complaint/CMP-1'), '/role');
      expect(go(demo, '/role'), isNull);
    });
  });
}
