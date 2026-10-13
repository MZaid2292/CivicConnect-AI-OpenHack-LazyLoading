import 'package:civicconnect_ai/app/app.dart';
import 'package:civicconnect_ai/core/config/app_config.dart';
import 'package:civicconnect_ai/core/di/app_dependencies.dart';
import 'package:civicconnect_ai/features/auth/presentation/cubit/session_cubit.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:civicconnect_ai/features/jobs/domain/work_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Drives the live-demo script through the real UI and dialogs.
void main() {
  late AppDependencies deps;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> switchRole(WidgetTester tester, String role) async {
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch role / log out').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue as $role'));
    await tester.pumpAndSettle();
  }

  void go(WidgetTester tester, String location) {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push(location);
  }

  testWidgets('admin → contractor → admin → citizen workflow via UI',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(
        {'demo_role': 'municipalAdmin', 'onboarding_seen': true});
    deps = AppDependencies(await SharedPreferences.getInstance(),
        config: const AppConfig.offline(),
        locationService: FakeLocationService(),
        mediaPicker: FakeMediaPicker());
    final session = SessionCubit(deps.sessionRepository);
    await tester.pumpWidget(BlocProvider.value(
        value: session, child: CivicConnectApp(dependencies: deps)));
    await session.restoreSession();
    await tester.pumpAndSettle();

    // Admin verifies the new garbage report and assigns Metro directly.
    go(tester, '/complaint/CMP-1007');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('verifyButton')));
    await tap(tester, find.widgetWithText(FilledButton, 'Verify'));
    expect((await deps.complaintRepository.findById('CMP-1007'))!.status,
        ComplaintStatus.verified);

    await tap(tester, find.byKey(const Key('assignButton')));
    await tap(tester, find.text('GreenCycle Sanitation'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Agreed amount (simulated Rs)'),
        '22000');
    await tap(tester, find.widgetWithText(FilledButton, 'Assign'));
    final c1007 = (await deps.complaintRepository.findById('CMP-1007'))!;
    expect(c1007.status, ComplaintStatus.assigned);
    expect(c1007.contractorId, 'ctr-green');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Contractor starts the awarded Canal Road job, adds evidence, submits.
    await switchRole(tester, 'Contractor');
    expect(find.text('Start work & add before photos'), findsOneWidget);
    go(tester, '/job/JOB-504');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('startWork')));
    await tap(tester, find.byKey(const Key('addAfter')));
    await tap(tester, find.text('Choose from gallery'));
    var job = (await deps.jobRepository.findById('JOB-504'))!;
    expect(job.status, JobStatus.inProgress);
    expect(job.afterPhotos, hasLength(1));
    expect(job.afterPhotos.first.isLocalOnly, isTrue);
    await tap(tester, find.byKey(const Key('requestCompletion')));
    await tap(tester, find.widgetWithText(FilledButton, 'Submit'));
    expect((await deps.complaintRepository.findById('CMP-1005'))!.status,
        ComplaintStatus.awaitingInspection);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Admin inspects and accepts.
    await switchRole(tester, 'Municipal Admin');
    go(tester, '/inspect/JOB-504');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('acceptWork')));
    await tap(tester, find.widgetWithText(FilledButton, 'Accept & resolve'));
    job = (await deps.jobRepository.findById('JOB-504'))!;
    expect(job.status, JobStatus.completed);
    expect(job.paymentStatus, PaymentStatus.releasedSimulated);
    expect((await deps.complaintRepository.findById('CMP-1005'))!.status,
        ComplaintStatus.resolved);

    // Citizen rates her resolved pothole report.
    await switchRole(tester, 'Citizen');
    go(tester, '/complaint/CMP-1001');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ratingForm')), findsOneWidget);
    await tap(tester, find.byTooltip('5 stars'));
    await tap(tester, find.text('Submit rating'));
    expect(
        (await deps.complaintRepository.findById('CMP-1001'))!.feedback!.rating,
        5);
    expect(find.byKey(const Key('ratingForm')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
