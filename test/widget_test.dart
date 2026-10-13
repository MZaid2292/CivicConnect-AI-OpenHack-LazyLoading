import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/services/media_picker_service.dart';
import 'package:civicconnect_ai/core/widgets/media_widgets.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  test('All three required roles are defined', () {
    expect(AppRole.values.length, 3);
    expect(AppRole.citizen.label, 'Citizen');
  });

  testWidgets('first launch shows onboarding, then the demo role selector',
      (tester) async {
    await bootApp(tester);
    expect(find.text('Get started'), findsOneWidget);
    await tapVisible(tester, find.text('Skip to demo role selector'));
    expect(find.textContaining('DEMO ROLE SELECTOR'), findsNothing);
    for (final role in ['Citizen', 'Municipal Admin', 'Contractor']) {
      expect(find.text('Continue as $role'), findsOneWidget);
    }
  });

  testWidgets('mock login validates format and leads to the role selector',
      (tester) async {
    await bootApp(tester);
    await tapVisible(tester, find.text('Get started'));
    expect(find.text('Continue (demo sign-in)'), findsOneWidget);
    await tapVisible(tester, find.text('Continue (demo sign-in)'));
    expect(find.text('Enter a valid email address'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tapVisible(tester, find.text('Continue (demo sign-in)'));
    expect(find.text('Continue as Citizen'), findsOneWidget);
  });

  testWidgets('saved demo role is restored on startup and logout clears it',
      (tester) async {
    await bootApp(tester, prefs: rolePrefs('citizen'));
    expect(find.textContaining('Ayesha'), findsWidgets,
        reason: 'personalised greeting');
    expect(find.text('Report issue'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Broken road with big holes on Canal Road'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.text('Broken road with big holes on Canal Road'), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch role / log out').last);
    await tester.pumpAndSettle();
    expect(find.text('Continue as Citizen'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('demo_role'), isNull);
  });

  testWidgets('category shortcut filters the citizen feed', (tester) async {
    await bootApp(tester, prefs: rolePrefs('citizen'));
    await tapVisible(tester, find.bySemanticsLabel(RegExp('^Streetlights, ')));
    expect(find.textContaining('match your filters'), findsOneWidget);
  });

  testWidgets('citizen report gets a category suggestion and reaches the queue',
      (tester) async {
    final deps = await bootApp(tester,
        prefs: rolePrefs('citizen'), size: const Size(1400, 1000));
    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('titleField')), 'Streetlight broken near bakery');
    await tester.enterText(find.byKey(const Key('descriptionField')),
        'The lamp post is dark every night and the lane feels unsafe.');
    await tester.enterText(
        find.byKey(const Key('addressField')), 'Bakery corner, Block 2');
    await tester.pumpAndSettle();

    // Suggestion comes from the rule-based classifier, not the UI.
    expect(find.textContaining('→ Streetlights'), findsOneWidget);
    expect(find.text('Rule-based NLP'), findsOneWidget);
    expect(find.text('Estimated priority'), findsOneWidget);

    // GPS denied by the fake: the form must fall back gracefully.
    await tapVisible(tester, find.text('Use my location'));
    expect(find.textContaining('permission denied'), findsOneWidget);

    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    final all = await deps.complaintRepository.listComplaints();
    final created = all.first;
    expect(created.title, 'Streetlight broken near bakery');
    expect(created.status, ComplaintStatus.submitted);
    expect(created.category, ComplaintCategory.streetlight);
    expect(find.text(created.id), findsWidgets, reason: 'detail page opened');

    // Same repository instance → visible to the admin immediately.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await switchRole(tester, 'Municipal Admin');
    await openTab(tester, 'Queue');
    expect(find.text('Streetlight broken near bakery'), findsOneWidget);
  });

  testWidgets('submitting an empty form shows validation feedback',
      (tester) async {
    await bootApp(tester, prefs: rolePrefs('citizen'));
    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 8 characters'), findsOneWidget);
    expect(find.text('Choose a category.'), findsOneWidget);
  });

  testWidgets('duplicate warning is driven by the detector', (tester) async {
    await bootApp(tester,
        prefs: rolePrefs('citizen'), size: const Size(1400, 1200));
    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('titleField')),
        'Garbage overflowing at Community Park entrance');
    await tester.enterText(find.byKey(const Key('descriptionField')),
        'Bins at the park gate are full and garbage is spilling out.');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('duplicateWarning')), findsOneWidget);
    expect(find.textContaining('CMP-1003'), findsWidgets);
    expect(find.textContaining('text-only'), findsWidgets);
  });

  testWidgets('citizen report photos: camera or gallery', (tester) async {
    final deps = await bootApp(tester, prefs: rolePrefs('citizen'));
    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Add photos'));
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    final picker = deps.mediaPicker as FakeMediaPicker;
    expect(picker.lastSource, MediaSource.camera);
    expect(find.byType(PhotoTile), findsOneWidget,
        reason: 'captured photo is previewed in the form');

    // A photo taken earlier (e.g. offline) can be picked from the gallery.
    await tapVisible(tester, find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(picker.lastSource, MediaSource.gallery);
    expect(find.byType(PhotoTile), findsNWidgets(2));

    // Dismissing the sheet (cancel) adds nothing and shows no error.
    await tapVisible(tester, find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
