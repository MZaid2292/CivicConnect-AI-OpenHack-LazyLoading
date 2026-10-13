import 'package:civicconnect_ai/core/widgets/civic_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'harness.dart';

/// Widths from the brief: small phone, phone, tablet, small laptop, desktop.
const widths = [320.0, 375.0, 768.0, 1024.0, 1440.0];

const roles = {
  'citizen': ['Home', 'My reports', 'Transparency', 'Profile'],
  'municipalAdmin': ['Overview', 'Queue', 'Duplicates', 'Work', 'Rules'],
  'contractor': ['Dashboard', 'Available', 'My jobs', 'Profile'],
};

void expectNavigationFor(double width) {
  if (width < 600) {
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'phones use bottom navigation');
    expect(find.byType(NavigationRail), findsNothing);
  } else if (width < 1200) {
    expect(find.byType(NavigationRail), findsOneWidget,
        reason: 'tablets use a navigation rail');
    expect(find.byType(NavigationBar), findsNothing);
  } else {
    expect(find.byType(CivicNavigationRail), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing,
        reason: 'desktop uses the extended sidebar');
    expect(find.byType(NavigationBar), findsNothing);
  }
}

void main() {
  for (final width in widths) {
    for (final entry in roles.entries) {
      testWidgets('${entry.key} dashboard at ${width.toInt()}px',
          (tester) async {
        await bootApp(tester,
            prefs: rolePrefs(entry.key), size: Size(width, 900));
        expectNavigationFor(width);
        for (final tab in entry.value) {
          await openTab(tester, tab);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('detail screens at ${width.toInt()}px', (tester) async {
      await bootApp(tester,
          prefs: rolePrefs('municipalAdmin'), size: Size(width, 900));
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      for (final route in [
        '/complaint/CMP-1001',
        '/complaint/CMP-1007',
        '/job/JOB-505',
        '/inspect/JOB-503',
        '/notifications',
        '/transparency',
      ]) {
        router.push(route);
        await tester.pumpAndSettle();
        // Scroll through the whole page so lazily built parts lay out too.
        final scrollable = find.byType(Scrollable).first;
        await tester.fling(scrollable, const Offset(0, -3000), 3000);
        await tester.pumpAndSettle();
        router.pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('landscape phone (740×360) keeps forms usable', (tester) async {
    await bootApp(tester,
        prefs: rolePrefs('citizen'), size: const Size(740, 360));
    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    expect(find.text('Submit report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding and role selector at 320px', (tester) async {
    await bootApp(tester, size: const Size(320, 640), textScale: 1.3);
    await tapVisible(tester, find.text('Skip to demo role selector'));
    await tapVisible(tester, find.text('Continue as Contractor'));
    expect(find.text('Hello, Metro Roads & Works'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
