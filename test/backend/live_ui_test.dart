import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/features/auth/domain/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';
import 'fake_backend.dart';

/// Live mode over local sample data: proves the approved auth/label changes
/// without a network. (Admin account used for deep links into sample data.)
FakeAuthRepository accounts({UserProfile? persisted}) => FakeAuthRepository(
      persisted: persisted,
      accounts: {
        'sana@example.com': ('correct-horse', citizenProfile()),
        'officer@example.com': (
          'correct-horse',
          const UserProfile(
            userId: 'adm-ward4',
            email: 'officer@example.com',
            displayName: 'Ward Officer',
            dbRole: 'municipal_admin',
            role: AppRole.municipalAdmin,
            municipalityId: 'muni-1',
            municipalityName: 'Karachi Metropolitan',
          ),
        ),
      },
    );

Future<void> signIn(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await tapVisible(tester, find.text('Sign in').last);
}

void main() {
  testWidgets('first launch: no demo shortcuts on welcome or sign-in',
      (tester) async {
    await bootApp(tester, auth: accounts());
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Skip to demo role selector'), findsNothing);
    await tapVisible(tester, find.text('Get started'));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsNWidgets(2),
        reason: 'mode toggle + real sign-in button');
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Skip — choose a demo role'), findsNothing);
    expect(find.textContaining('demo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong password shows the server message and stays signed out',
      (tester) async {
    await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
    await signIn(tester, 'sana@example.com', 'wrong-password');
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('sign-in opens the dashboard with the real identity',
      (tester) async {
    await bootApp(tester, auth: accounts(), prefs: {'onboarding_seen': true});
    await signIn(tester, 'sana@example.com', 'correct-horse');
    expect(find.textContaining('Sana'), findsWidgets);
    expect(find.text('Karachi Metropolitan'), findsOneWidget,
        reason: 'municipality from the profile, not "Ward 4"');
    expect(find.textContaining('Ward 4'), findsNothing);
    expect(find.text('Report issue'), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('demo identity'), findsNothing);
    await tester.tap(find.text('Log out').last);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue as Citizen'), findsNothing);
  });

  testWidgets('a deep link survives sign-in', (tester) async {
    await bootApp(tester,
        auth: accounts(),
        prefs: {'onboarding_seen': true},
        initialLocation: '/complaint/CMP-1007');
    expect(find.text('Welcome back'), findsOneWidget);
    await tapVisible(tester, find.text('Municipal Admin'));
    await signIn(tester, 'officer@example.com', 'correct-horse');
    expect(find.text('CMP-1007'), findsWidgets,
        reason: 'the requested complaint opens after sign-in');
  });

  testWidgets('forgot password sends a reset link', (tester) async {
    final auth = accounts();
    await bootApp(tester, auth: auth, prefs: {'onboarding_seen': true});
    await tester.enterText(
        find.byType(TextFormField).at(0), 'sana@example.com');
    await tapVisible(tester, find.text('Forgot password?'));
    expect(find.text('Reset password'), findsOneWidget);
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();
    expect(auth.resetRequests, ['sana@example.com']);
    expect(find.textContaining('reset link is on its way'), findsOneWidget);
  });

  testWidgets('a password-reset link asks for a new password', (tester) async {
    final auth = accounts(persisted: citizenProfile());
    await bootApp(tester, auth: auth);
    auth.emit(AuthEvent.passwordRecovery);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextFormField)),
        'brand-new-pass');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(auth.updatedPassword, 'brand-new-pass');
  });

  testWidgets('report photos are camera-only with truthful storage text',
      (tester) async {
    await bootApp(tester, auth: accounts(persisted: citizenProfile()));
    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('uploaded privately'), findsOneWidget);
    expect(find.textContaining('stays on this device'), findsNothing);
    await tapVisible(tester, find.text('Add photos'));
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsNothing);
    expect(find.textContaining('private storage'), findsOneWidget);
  });
}
