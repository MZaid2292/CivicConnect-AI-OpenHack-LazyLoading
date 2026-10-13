import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/models/workflow_exception.dart';
import 'package:civicconnect_ai/features/auth/data/contractor_applications.dart';
import 'package:civicconnect_ai/features/auth/data/local_session_repository.dart';
import 'package:civicconnect_ai/features/auth/domain/auth_repository.dart';
import 'package:civicconnect_ai/features/auth/domain/login_role_check.dart';
import 'package:civicconnect_ai/features/auth/presentation/cubit/session_cubit.dart';
import 'package:civicconnect_ai/features/jobs/domain/contractor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';
import 'fake_backend.dart';

UserProfile profile(
        {String dbRole = 'citizen',
        AppRole? role = AppRole.citizen,
        String? municipalityId = 'muni-1',
        ContractorStatus? contractorStatus}) =>
    UserProfile(
      userId: 'u1',
      email: 'x@example.com',
      displayName: 'X',
      dbRole: dbRole,
      role: role,
      municipalityId: municipalityId,
      contractorId: contractorStatus == null ? null : 'c1',
      contractorStatus: contractorStatus,
    );

final admin = profile(dbRole: 'municipal_admin', role: AppRole.municipalAdmin);
final approvedContractor = profile(
    dbRole: 'contractor',
    role: AppRole.contractor,
    contractorStatus: ContractorStatus.approved);

FakeAuthRepository accounts() => FakeAuthRepository(accounts: {
      'sana@example.com': ('correct-horse', citizenProfile()),
      'officer@example.com': ('correct-horse', admin),
      'works@example.com': ('correct-horse', approvedContractor),
    });

Future<void> fill(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
}

Future<void> signInAs(WidgetTester tester, String role, String email) async {
  await tapVisible(tester, find.text(role));
  await fill(tester, 'Email', email);
  await fill(tester, 'Password', 'correct-horse');
  await tapVisible(tester, find.text('Sign in').last);
}

void main() {
  group('LoginRoleCheck (selected role vs trusted database role)', () {
    test('citizen selection accepts citizen accounts only', () {
      expect(LoginRoleCheck.problem(citizenProfile(), AppRole.citizen), isNull);
      expect(LoginRoleCheck.problem(admin, AppRole.citizen), isNotNull);
      expect(LoginRoleCheck.problem(approvedContractor, AppRole.citizen),
          isNotNull);
    });

    test('municipal admin selection needs the role and a municipality', () {
      expect(LoginRoleCheck.problem(admin, AppRole.municipalAdmin), isNull);
      expect(
          LoginRoleCheck.problem(citizenProfile(), AppRole.municipalAdmin)!
              .message,
          contains('not a municipal admin'));
      final noMunicipality = profile(
          dbRole: 'municipal_admin',
          role: AppRole.municipalAdmin,
          municipalityId: null);
      expect(
          LoginRoleCheck.problem(noMunicipality, AppRole.municipalAdmin)!
              .message,
          contains('no municipality'));
    });

    test('contractor selection needs an approved contractor record', () {
      expect(LoginRoleCheck.problem(approvedContractor, AppRole.contractor),
          isNull);
      final pending =
          profile(contractorStatus: ContractorStatus.pendingApproval);
      final p = LoginRoleCheck.problem(pending, AppRole.contractor)!;
      expect(p.pendingApproval, isTrue);
      final rejected = profile(contractorStatus: ContractorStatus.rejected);
      expect(LoginRoleCheck.problem(rejected, AppRole.contractor)!.message,
          contains('not approved'));
      expect(
          LoginRoleCheck.problem(citizenProfile(), AppRole.contractor)!.message,
          contains('not registered as a contractor'));
      final roleWithoutRecord =
          profile(dbRole: 'contractor', role: AppRole.contractor);
      expect(LoginRoleCheck.problem(roleWithoutRecord, AppRole.contractor),
          isNotNull);
    });
  });

  group('ContractorApplications (existing contractors table + RLS)', () {
    late FakeDb db;
    late ContractorApplications apps;
    const app = ContractorApplication(
        businessName: ' Metro Works ',
        municipalityId: 'muni-1',
        municipalityName: 'Karachi Metropolitan',
        description: 'Roads');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = FakeDb(currentUserId: 'u1', tables: {
        'municipalities': [
          {'id': 'muni-2', 'name': 'Lahore'},
          {'id': 'muni-1', 'name': 'Karachi Metropolitan'},
        ],
      });
      apps = ContractorApplications(db, await SharedPreferences.getInstance());
    });

    test('lists municipalities by name', () async {
      final list = await apps.listMunicipalities();
      expect(list.map((m) => m.name), ['Karachi Metropolitan', 'Lahore']);
    });

    test('an unreadable municipality list gives a clear message', () async {
      db.tables.remove('municipalities');
      final failing = _FailingSelectDb();
      final a = ContractorApplications(
          failing, await SharedPreferences.getInstance());
      await expectLater(a.listMunicipalities(),
          throwsA(predicate((e) => '$e'.contains('could not be loaded'))));
    });

    test('creates one pending application for the signed-in user', () async {
      expect(await apps.submit('u1', app), isTrue);
      final row = db.table('contractors').single;
      expect(row['owner_id'], 'u1');
      expect(row['business_name'], 'Metro Works');
      expect(row['municipality_id'], 'muni-1');
      expect(row['verification_status'], 'pending');
      expect(db.rpcCalls, isEmpty, reason: 'no privileged function is used');
      expect(await apps.submit('u1', app), isFalse,
          reason: 'duplicate applications are not created');
      expect(db.table('contractors'), hasLength(1));
    });

    test('pending details are kept without a password until confirmed',
        () async {
      await apps.savePending('Works@Example.com', app);
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('pending_contractor_application')!;
      expect(stored, isNot(contains('password')));
      expect(apps.pendingFor('other@example.com'), isNull);
      expect(await apps.completePending('u1', 'works@example.com'), isTrue);
      expect(db.table('contractors'), hasLength(1));
      expect(prefs.getString('pending_contractor_application'), isNull);
      expect(await apps.completePending('u1', 'works@example.com'), isFalse);
    });
  });

  group('SessionCubit role-checked sign-in', () {
    Future<(SessionCubit, FakeAuthRepository)> cubit(
        {UserProfile? persisted}) async {
      SharedPreferences.setMockInitialValues({});
      final auth = accounts()..persisted = persisted;
      final c = SessionCubit(
          LocalSessionRepository(await SharedPreferences.getInstance()),
          auth: auth);
      await c.restoreSession();
      return (c, auth);
    }

    test('a role mismatch signs out and exposes nothing', () async {
      final (c, auth) = await cubit();
      await expectLater(
          c.signIn('sana@example.com', 'correct-horse',
              as: AppRole.municipalAdmin),
          throwsA(isA<RoleAccessException>()));
      expect(c.state.actor, isNull);
      expect(auth.currentProfile, isNull);
    });

    test('matching roles open the trusted dashboard', () async {
      final (c, _) = await cubit();
      await c.signIn('officer@example.com', 'correct-horse',
          as: AppRole.municipalAdmin);
      expect(c.state.role, AppRole.municipalAdmin);
      await c.logout();
      await c.signIn('works@example.com', 'correct-horse',
          as: AppRole.contractor);
      expect(c.state.role, AppRole.contractor);
    });

    test('contractor sign-up never opens a contractor session', () async {
      final (c, auth) = await cubit();
      final outcome = await c.signUpContractor(
          'Ali',
          'new@example.com',
          'password1',
          const ContractorApplication(
              businessName: 'Ali Builders', municipalityId: 'muni-1'));
      expect(outcome, ContractorSignUpOutcome.submitted);
      expect(c.state.actor, isNull);
      expect(auth.applications.keys, ['new@example.com']);
      await expectLater(
          c.signIn('new@example.com', 'password1', as: AppRole.contractor),
          throwsA(
              predicate((e) => e is RoleAccessException && e.pendingApproval)));
      expect(c.state.actor, isNull);
    });

    test('an existing session is restored by database role', () async {
      final (c, _) = await cubit(persisted: approvedContractor);
      expect(c.state.role, AppRole.contractor);
      expect(c.state.actor, isNotNull);
    });
  });

  group('sign-in screen (live)', () {
    testWidgets('offers Citizen, Municipal Admin and Contractor',
        (tester) async {
      await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
      for (final role in ['Citizen', 'Municipal Admin', 'Contractor']) {
        expect(find.text(role), findsOneWidget);
      }
      expect(find.text('Sign up'), findsOneWidget);
    });

    testWidgets('no public municipal admin sign-up', (tester) async {
      await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
      await tapVisible(tester, find.text('Sign up'));
      await tapVisible(tester, find.text('Municipal Admin'));
      expect(find.text('Sign up'), findsNothing);
      expect(find.text('Create account'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('citizen sign-up opens the citizen dashboard', (tester) async {
      await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
      await tapVisible(tester, find.text('Sign up'));
      await fill(tester, 'Full name', 'Nida Khan');
      await fill(tester, 'Email', 'nida@example.com');
      await fill(tester, 'Password', 'password1');
      await tapVisible(tester, find.text('Create account'));
      expect(find.text('Report issue'), findsOneWidget);
    });

    testWidgets('role mismatch is refused on the sign-in screen',
        (tester) async {
      await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
      await signInAs(tester, 'Municipal Admin', 'sana@example.com');
      expect(find.textContaining('not a municipal admin'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Overview'), findsNothing);
    });

    testWidgets('municipal admin signs in to the admin dashboard',
        (tester) async {
      await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
      await signInAs(tester, 'Municipal Admin', 'officer@example.com');
      expect(find.text('Overview'), findsWidgets);
    });

    testWidgets('contractor applies, waits, then signs in after approval',
        (tester) async {
      final auth = accounts();
      await bootApp(tester, auth: auth, prefs: {'onboarding_seen': true});
      await tapVisible(tester, find.text('Contractor'));
      await tapVisible(tester, find.text('Sign up'));
      expect(find.byKey(const Key('businessNameField')), findsOneWidget);
      expect(find.byKey(const Key('municipalityField')), findsOneWidget);

      await fill(tester, 'Full name', 'Ali Raza');
      await fill(tester, 'Business / company name', 'Ali Builders');
      await tapVisible(tester, find.byKey(const Key('municipalityField')));
      await tester.tap(find.text('Karachi Metropolitan').last);
      await tester.pumpAndSettle();
      await fill(tester, 'Email', 'ali@example.com');
      await fill(tester, 'Password', 'password1');
      await tapVisible(tester, find.text('Submit application'));

      expect(find.text('Application submitted'), findsOneWidget);
      expect(auth.applications['ali@example.com']!.municipalityId, 'muni-1');

      // Pending: contractor sign-in shows the pending banner, no dashboard.
      await fill(tester, 'Email', 'ali@example.com');
      await fill(tester, 'Password', 'password1');
      await tapVisible(tester, find.text('Sign in').last);
      expect(find.text('Application pending'), findsOneWidget);
      expect(find.text('Available'), findsNothing);

      // Municipal approval (verify_contractor) → contractor dashboard.
      auth.decide('ali@example.com', approve: true);
      await tapVisible(tester, find.text('Sign in').last);
      expect(find.text('Available'), findsWidgets);
    });

    testWidgets('email confirmation: application is sent on first sign-in',
        (tester) async {
      final auth = accounts()..confirmEmailOnSignUp = true;
      await bootApp(tester, auth: auth, prefs: {'onboarding_seen': true});
      await tapVisible(tester, find.text('Contractor'));
      await tapVisible(tester, find.text('Sign up'));
      await fill(tester, 'Full name', 'Ali Raza');
      await fill(tester, 'Business / company name', 'Ali Builders');
      await tapVisible(tester, find.byKey(const Key('municipalityField')));
      await tester.tap(find.text('Karachi Metropolitan').last);
      await tester.pumpAndSettle();
      await fill(tester, 'Email', 'ali@example.com');
      await fill(tester, 'Password', 'password1');
      await tapVisible(tester, find.text('Submit application'));
      expect(find.text('Confirm your email'), findsOneWidget);
      expect(auth.applications, isEmpty);

      await fill(tester, 'Password', 'password1');
      await tapVisible(tester, find.text('Sign in').last);
      expect(auth.applications.keys, ['ali@example.com']);
      expect(find.text('Application pending'), findsOneWidget);
    });

    testWidgets('fits 320 px with 2.0× text', (tester) async {
      await bootApp(tester,
          auth: accounts(),
          prefs: {'onboarding_seen': true},
          size: const Size(320, 640),
          textScale: 2.0);
      await tapVisible(tester, find.text('Contractor'));
      await tapVisible(tester, find.text('Sign up'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

class _FailingSelectDb extends FakeDb {
  @override
  Future<List<Map<String, dynamic>>> select(String t,
          {String columns = '*',
          Map<String, Object> eq = const {},
          String? inColumn,
          List<Object>? inValues,
          String? orderBy,
          bool ascending = false,
          int? limit}) async =>
      throw const WorkflowException('You do not have permission to do that.');
}
