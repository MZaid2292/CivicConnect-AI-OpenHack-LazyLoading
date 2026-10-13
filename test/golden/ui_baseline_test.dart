// Visual regression baseline for the approved UI. Regenerate ONLY when a UI
// change is intentionally approved:
//   flutter test test/golden --update-goldens
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../harness.dart';

/// Allows a tiny pixel difference so clock-dependent text (today's date on
/// the admin overview, the time-of-day greeting) doesn't fail the baseline,
/// while any layout, colour or spacing change still does.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);
  static const tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
        imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

const _screens = <String, List<String>>{
  // role: [tab labels or routes]
  'citizen': ['tab:Home', 'route:/report/new', 'route:/complaint/CMP-1001'],
  'municipalAdmin': [
    'tab:Overview',
    'tab:Queue',
    'tab:Duplicates',
    'tab:Work',
    'tab:Rules',
  ],
  'contractor': ['tab:Dashboard', 'route:/job/JOB-504'],
};

const _variants = {
  'phone_light': (Size(390, 844), Brightness.light),
  'phone_dark': (Size(390, 844), Brightness.dark),
  'desktop_light': (Size(1280, 800), Brightness.light),
};

String _slug(String s) =>
    s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'_$'), '');

void main() {
  setUpAll(() {
    final current = goldenFileComparator as LocalFileComparator;
    goldenFileComparator =
        _TolerantComparator(current.basedir.resolve('ui_baseline_test.dart'));
  });

  for (final MapEntry(key: variant, value: (size, brightness))
      in _variants.entries) {
    testWidgets('auth screens · $variant', (tester) async {
      await bootApp(tester, size: size, brightness: brightness);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('baseline/auth_welcome_$variant.png'));
      await tapVisible(tester, find.text('Get started'));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('baseline/auth_login_$variant.png'));
      await tapVisible(tester, find.text('Skip — choose a demo role'));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('baseline/auth_roles_$variant.png'));
    });

    for (final MapEntry(key: role, value: screens) in _screens.entries) {
      testWidgets('$role screens · $variant', (tester) async {
        await bootApp(tester,
            prefs: rolePrefs(role), size: size, brightness: brightness);
        for (final screen in screens) {
          final (kind, target) = (
            screen.substring(0, screen.indexOf(':')),
            screen.substring(screen.indexOf(':') + 1),
          );
          if (kind == 'tab') {
            await openTab(tester, target);
          } else {
            GoRouter.of(tester.element(find.byType(Scaffold).first))
                .push(target);
            await tester.pumpAndSettle();
          }
          await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                  'baseline/${role}_${_slug(target)}_$variant.png'));
          if (kind == 'route') {
            GoRouter.of(tester.element(find.byType(Scaffold).last)).pop();
            await tester.pumpAndSettle();
          }
        }
      });
    }
  }
}
