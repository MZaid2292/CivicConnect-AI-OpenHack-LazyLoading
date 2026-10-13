import 'dart:math' as math;

import 'package:civicconnect_ai/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

ThemeData _activeTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

void main() {
  group('Design tokens', () {
    for (final (name, theme) in [
      ('light', AppTheme.lightTheme),
      ('dark', AppTheme.darkTheme),
    ]) {
      test('$name theme has readable text contrast and civic tokens', () {
        final s = theme.colorScheme;
        final palette = theme.extension<CivicPalette>()!;
        expect(_contrast(s.onSurface, s.surface), greaterThanOrEqualTo(7));
        expect(_contrast(s.onSurface, theme.scaffoldBackgroundColor),
            greaterThanOrEqualTo(7));
        expect(_contrast(palette.muted, s.surface), greaterThanOrEqualTo(4.5),
            reason: 'secondary text meets WCAG AA');
        expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
        expect(palette.isDark, name == 'dark');
      });
    }

    test('status hues are toned for dark surfaces', () {
      final dark = AppTheme.darkTheme;
      final p = dark.extension<CivicPalette>()!;
      for (final hue in [
        AppColors.red,
        AppColors.amber,
        AppColors.teal,
        AppColors.purple,
        AppColors.indigo,
      ]) {
        expect(_contrast(p.tone(hue), dark.colorScheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'badge text stays readable in dark mode');
      }
    });
  });

  testWidgets('light system appearance renders the light theme',
      (tester) async {
    await bootApp(tester, prefs: rolePrefs('citizen'));
    final theme = _activeTheme(tester);
    expect(theme.brightness, Brightness.light);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark system appearance renders the dark theme', (tester) async {
    await bootApp(tester,
        prefs: rolePrefs('citizen'), brightness: Brightness.dark);
    expect(_activeTheme(tester).brightness, Brightness.dark);
    expect(_activeTheme(tester).scaffoldBackgroundColor,
        AppTheme.darkTheme.scaffoldBackgroundColor);
    // Profile reports the live appearance.
    await openTab(tester, 'Profile');
    expect(find.textContaining('currently Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching the OS theme at runtime updates the app',
      (tester) async {
    await bootApp(tester, prefs: rolePrefs('municipalAdmin'));
    expect(_activeTheme(tester).brightness, Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(_activeTheme(tester).brightness, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(_activeTheme(tester).brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode renders every role dashboard and detail screens',
      (tester) async {
    await bootApp(tester,
        prefs: rolePrefs('citizen'),
        brightness: Brightness.dark,
        size: const Size(1024, 900));
    await tapVisible(tester, find.text('Report issue'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await switchRole(tester, 'Municipal Admin');
    for (final tab in ['Queue', 'Duplicates', 'Work', 'Rules']) {
      await openTab(tester, tab);
    }
    await switchRole(tester, 'Contractor');
    for (final tab in ['Available', 'My jobs', 'Profile']) {
      await openTab(tester, tab);
    }
    expect(tester.takeException(), isNull);
  });
}
