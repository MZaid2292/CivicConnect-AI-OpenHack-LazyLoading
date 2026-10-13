import 'dart:ui';

import 'package:civicconnect_ai/app/app.dart';
import 'package:civicconnect_ai/core/config/app_config.dart';
import 'package:civicconnect_ai/core/di/app_dependencies.dart';
import 'package:civicconnect_ai/features/auth/domain/auth_repository.dart';
import 'package:civicconnect_ai/features/auth/presentation/cubit/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Boots the real app with mock services at a given logical [size],
/// platform [brightness], [textScale] and optional keyboard inset.
/// [initialLocation] simulates opening (or reloading) that URL in a browser.
Future<AppDependencies> bootApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Size size = const Size(420, 900),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  double keyboardInset = 0,
  String? initialLocation,
  AuthRepository? auth,
}) async {
  if (initialLocation != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = initialLocation;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (keyboardInset > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  }
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  SharedPreferences.setMockInitialValues(prefs);
  final deps = AppDependencies(await SharedPreferences.getInstance(),
      config: const AppConfig.offline(),
      locationService: FakeLocationService(),
      mediaPicker: FakeMediaPicker(),
      authRepository: auth);
  final session = SessionCubit(deps.sessionRepository, auth: auth);
  await tester.pumpWidget(BlocProvider.value(
      value: session, child: CivicConnectApp(dependencies: deps)));
  await session.restoreSession();
  await tester.pumpAndSettle();
  return deps;
}

Map<String, Object> rolePrefs(String role) =>
    {'demo_role': role, 'onboarding_seen': true};

/// Scrolls [finder] into view (if inside a scrollable) and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Logs out through the account menu and continues as [roleLabel].
Future<void> switchRole(WidgetTester tester, String roleLabel) async {
  await tester.tap(find.byTooltip('Account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Switch role / log out').last);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text('Continue as $roleLabel'));
}

/// Taps a navigation destination by label (works for bottom bar, rail and
/// sidebar — the navigation label is the last matching text). At large text
/// sizes the bottom bar hides unselected labels, so fall back to the
/// destination's tooltip.
Future<void> openTab(WidgetTester tester, String label) async {
  final visible = find.text(label).hitTestable();
  await tester.tap(visible.evaluate().isNotEmpty
      ? visible.last
      : find.byTooltip(label).last);
  await tester.pumpAndSettle();
}
