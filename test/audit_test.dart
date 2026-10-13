import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'harness.dart';
import 'responsive_test.dart' show expectNavigationFor, roles;

/// Detail routes reachable by each role.
const detailRoutes = {
  'citizen': [
    '/report/new',
    '/complaint/CMP-1001',
    '/complaint/CMP-1007',
    '/notifications',
  ],
  'municipalAdmin': [
    '/complaint/CMP-1008',
    '/job/JOB-505',
    '/inspect/JOB-503',
    '/transparency',
  ],
  'contractor': ['/job/JOB-504', '/job/JOB-505', '/notifications'],
};

/// Scrolls every visible vertical list to its end, a viewport at a time, so
/// lazily built content is laid out (and any overflow is reported).
Future<void> scrollThrough(WidgetTester tester) async {
  final states = [
    for (final e in find.byType(Scrollable).hitTestable().evaluate())
      if (e is StatefulElement && e.state is ScrollableState)
        e.state as ScrollableState,
  ].where((s) => s.position.axis == Axis.vertical);
  for (final s in states) {
    for (var i = 0; i < 25; i++) {
      final p = s.position;
      if (p.pixels >= p.maxScrollExtent) break;
      p.jumpTo(
          (p.pixels + p.viewportDimension * 0.8).clamp(0.0, p.maxScrollExtent));
      await tester.pump();
    }
  }
  await tester.pumpAndSettle();
}

/// Opens every tab and detail screen for [role], scrolling each to the end.
Future<void> sweepRole(WidgetTester tester, String role) async {
  for (final tab in roles[role]!) {
    await openTab(tester, tab);
    await scrollThrough(tester);
    if (tab == 'Work') {
      await tester.tap(find.text('Contractors').last);
      await tester.pumpAndSettle();
      await scrollThrough(tester);
    }
    expect(tester.takeException(), isNull, reason: '$role › $tab');
  }
  final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
  for (final route in detailRoutes[role]!) {
    router.push(route);
    await tester.pumpAndSettle();
    await scrollThrough(tester);
    expect(tester.takeException(), isNull, reason: '$role › $route');
    router.pop();
    await tester.pumpAndSettle();
  }
}

void main() {
  group('320px with 2.0× text', () {
    for (final role in roles.keys) {
      testWidgets('$role screens have no overflow', (tester) async {
        await bootApp(tester,
            prefs: rolePrefs(role), size: const Size(320, 640), textScale: 2.0);
        await sweepRole(tester, role);
      });
    }
  });

  group('landscape', () {
    const sizes = [Size(740, 360), Size(915, 412), Size(1280, 800)];
    for (final size in sizes) {
      for (final role in roles.keys) {
        testWidgets('$role at ${size.width.toInt()}×${size.height.toInt()}',
            (tester) async {
          await bootApp(tester, prefs: rolePrefs(role), size: size);
          expectNavigationFor(size.width);
          await sweepRole(tester, role);
        });
      }
    }
  });

  group('web deep links', () {
    testWidgets('reloading a complaint URL reopens that complaint',
        (tester) async {
      await bootApp(tester,
          prefs: rolePrefs('citizen'), initialLocation: '/complaint/CMP-1007');
      expect(find.text('CMP-1007'), findsWidgets);
      expect(find.byType(Hero), findsNothing,
          reason: 'no source card on a fresh load, so no Hero');
      // Nothing to pop after a reload: the app bar offers a way home.
      await tester.tap(find.byTooltip('Back to home'));
      await tester.pumpAndSettle();
      expect(find.text('Report issue'), findsOneWidget);
    });

    testWidgets('a reload without a saved role asks for one first',
        (tester) async {
      await bootApp(tester,
          prefs: {'onboarding_seen': true},
          initialLocation: '/complaint/CMP-1007');
      expect(find.text('Continue as Citizen'), findsOneWidget);
    });

    testWidgets('role guards still apply to deep links', (tester) async {
      await bootApp(tester,
          prefs: rolePrefs('citizen'), initialLocation: '/inspect/JOB-503');
      expect(find.text('Report issue'), findsOneWidget,
          reason: 'citizens are sent home from admin-only routes');
    });

    testWidgets('in-app navigation keeps the Hero transition', (tester) async {
      await bootApp(tester, prefs: rolePrefs('citizen'));
      final card = find.text('Broken road with big holes on Canal Road');
      await tester.scrollUntilVisible(card, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final heroes = find.byType(Hero).evaluate().length;
      expect(heroes, greaterThan(0));
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Mid-flight the Hero is drawn in the overlay above both routes.
      expect(find.byType(Hero), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('Back to home'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget,
          reason: 'normal back button when opened in-app');
    });
  });

  group('admin review tools', () {
    testWidgets('duplicate merge asks for confirmation', (tester) async {
      final deps = await bootApp(tester,
          prefs: rolePrefs('municipalAdmin'), size: const Size(1280, 900));
      await openTab(tester, 'Duplicates');
      expect(find.text('Review flagged pairs'), findsOneWidget);
      expect(find.text('How matches are scored'), findsOneWidget);
      final merge = find.textContaining('Merge into CMP-1005');
      await tapVisible(tester, merge.first);
      expect(find.text('Merge CMP-1008?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      var c = await deps.complaintRepository.findById('CMP-1008');
      expect(c!.status, isNot(ComplaintStatus.duplicate));

      await tapVisible(tester, merge.first);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      c = await deps.complaintRepository.findById('CMP-1008');
      expect(c!.status, ComplaintStatus.duplicate);
      expect(find.textContaining('merged into CMP-1005'), findsOneWidget);
    });

    testWidgets('keeping a report separate clears it from review',
        (tester) async {
      await bootApp(tester,
          prefs: rolePrefs('municipalAdmin'), size: const Size(375, 800));
      await openTab(tester, 'Duplicates');
      await tapVisible(tester, find.text('Not a duplicate').first);
      expect(
          find.textContaining('marked as a distinct report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rules editor tracks unsaved changes and saves',
        (tester) async {
      final deps = await bootApp(tester,
          prefs: rolePrefs('municipalAdmin'), size: const Size(1280, 900));
      await openTab(tester, 'Rules');
      expect(find.textContaining('All changes saved', findRichText: true),
          findsOneWidget);
      final save = find.byKey(const Key('saveRules'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      final slider = find.descendant(
          of: find
              .ancestor(
                  of: find.text('Per supporter'), matching: find.byType(Column))
              .first,
          matching: find.byType(Slider));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsaved draft', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Unsaved changes', findRichText: true),
          findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('All changes saved', findRichText: true),
          findsOneWidget);
      expect(deps.complaintService.rules.pointsPerSupporter, isNot(3),
          reason: 'saved through the domain service');
    });
  });
}
