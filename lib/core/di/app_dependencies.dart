import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/local_session_repository.dart';
import '../../features/auth/domain/session_repository.dart';
import '../../features/complaints/data/mock_complaint_repository.dart';
import '../../features/complaints/domain/complaint_repository.dart';
import '../../features/complaints/domain/priority_rules_repository.dart';
import '../../features/complaints/domain/services/complaint_service.dart';
import '../../features/jobs/data/mock_job_repositories.dart';
import '../../features/jobs/domain/job_repositories.dart';
import '../../features/jobs/domain/job_service.dart';
import '../../features/notifications/data/in_memory_notification_repository.dart';
import '../../features/notifications/domain/app_notification.dart';
import '../config/app_config.dart';
import '../data/demo_seed.dart';
import '../services/location_service.dart';
import '../services/media_picker_service.dart';

/// Composition root. A single instance of every repository/service is shared
/// by all roles, so a citizen's report shows up in the admin queue instantly.
///
/// To move to Supabase, swap the Mock* repositories here for Supabase-backed
/// implementations of the same interfaces.
class AppDependencies {
  AppDependencies._({
    required this.config,
    required this.sessionRepository,
    required this.complaintRepository,
    required this.jobRepository,
    required this.contractorRepository,
    required this.notificationRepository,
    required this.priorityRulesRepository,
    required this.complaintService,
    required this.jobService,
    required this.locationService,
    required this.mediaPicker,
  });

  factory AppDependencies(
    SharedPreferences preferences, {
    AppConfig config = const AppConfig(),
    LocationService? locationService,
    MediaPickerService? mediaPicker,
    DateTime Function()? clock,
  }) {
    final now = (clock ?? DateTime.now)();
    final seed = DemoSeed(now: now, center: config.defaultCenter);
    final complaints = MockComplaintRepository(seed.complaints());
    final jobs = MockJobRepository(seed.jobs());
    final contractors = MockContractorRepository(seed.contractors());
    final notifications = InMemoryNotificationRepository(seed.notifications());
    final rules = InMemoryPriorityRulesRepository();
    final complaintService = ComplaintService(
      complaints: complaints,
      rules: rules,
      contractors: contractors,
      notifications: notifications,
      clock: clock,
    );
    return AppDependencies._(
      config: config,
      sessionRepository: LocalSessionRepository(preferences),
      complaintRepository: complaints,
      jobRepository: jobs,
      contractorRepository: contractors,
      notificationRepository: notifications,
      priorityRulesRepository: rules,
      complaintService: complaintService,
      jobService: JobService(
        jobs: jobs,
        contractors: contractors,
        complaints: complaintService,
        notifications: notifications,
        clock: clock,
      ),
      locationService: locationService ?? const GeolocatorLocationService(),
      mediaPicker: mediaPicker ?? ImagePickerMediaService(),
    );
  }

  final AppConfig config;
  final SessionRepository sessionRepository;
  final ComplaintRepository complaintRepository;
  final JobRepository jobRepository;
  final ContractorRepository contractorRepository;
  final NotificationRepository notificationRepository;
  final PriorityRulesRepository priorityRulesRepository;
  final ComplaintService complaintService;
  final JobService jobService;
  final LocationService locationService;
  final MediaPickerService mediaPicker;
}
