import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'harness.dart';

/// Forms must stay usable with large text and an open on-screen keyboard.
void main() {
  for (final scale in [1.3, 2.0]) {
    testWidgets('report form at 320px, text scale $scale, keyboard open',
        (tester) async {
      await bootApp(tester,
          prefs: rolePrefs('citizen'),
          size: const Size(320, 640),
          textScale: scale,
          keyboardInset: 260);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .push('/report/new');
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('titleField')),
          'Deep pothole near the clinic gate');
      await tester.enterText(find.byKey(const Key('descriptionField')),
          'Large pothole, an accident happened last night near the school.');
      await tester.pumpAndSettle();

      // The focused field is visible above the keyboard.
      final field = tester.getRect(find.byKey(const Key('descriptionField')));
      expect(field.top, lessThan(640 - 260));

      // Everything below remains reachable by scrolling.
      await tester.scrollUntilVisible(find.text('Use my location'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.byKey(const Key('addressField')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mock login at 320px with 2.0 text scale and keyboard',
      (tester) async {
    await bootApp(tester,
        size: const Size(320, 640), textScale: 2.0, keyboardInset: 260);
    await tapVisible(tester, find.text('Get started'));
    await tapVisible(tester, find.text('Sign up'));
    await tester.enterText(find.byType(TextFormField).first, 'Test User');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('complaint detail and bid sheet at 320px with large text',
      (tester) async {
    await bootApp(tester,
        prefs: rolePrefs('contractor'),
        size: const Size(320, 700),
        textScale: 1.5);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.push('/job/JOB-505');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('bidButton')));
    expect(find.text('Submit bid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive elements expose semantics labels', (tester) async {
    final handle = tester.ensureSemantics();
    await bootApp(tester, prefs: rolePrefs('citizen'));
    expect(find.bySemanticsLabel(RegExp('Report issue')), findsWidgets);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip(RegExp('Notifications')), findsOneWidget);
    handle.dispose();
  });
}
