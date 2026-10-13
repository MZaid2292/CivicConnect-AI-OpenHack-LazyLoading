import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/contractor_applications.dart';
import '../../features/auth/data/local_session_repository.dart';
import '../../features/auth/data/supabase_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/session_repository.dart';
import '../../features/complaints/data/mock_complaint_repository.dart';
import '../../features/complaints/data/supabase_complaint_repository.dart';
import '../../features/complaints/data/supabase_complaint_service.dart';
import '../../features/complaints/data/supabase_priority_rules_repository.dart';
import '../../features/complaints/domain/complaint_repository.dart';
import '../../features/complaints/domain/priority_rules_repository.dart';
import '../../features/complaints/domain/services/complaint_service.dart';
import '../../features/jobs/data/mock_job_repositories.dart';
import '../../features/jobs/data/supabase_job_repositories.dart';
import '../../features/jobs/data/supabase_job_service.dart';
import '../../features/jobs/domain/job_repositories.dart';
import '../../features/jobs/domain/job_service.dart';
import '../../features/notifications/data/in_memory_notification_repository.dart';
import '../../features/notifications/data/supabase_notification_repository.dart';
import '../../features/notifications/domain/app_notification.dart';
import '../backend_mode.dart';
import '../config/app_config.dart';
import '../data/demo_seed.dart';
import '../services/location_service.dart';
import '../services/media_picker_service.dart';
import '../services/reverse_geocoder.dart';
import '../supabase/db_gateway.dart';
import '../supabase/live_sync.dart';
import '../supabase/media_store.dart';

class AppDependencies {
  AppDependencies._({
    this.mode = const BackendMode.local(),
    this.authRepository,
    this.liveSync,
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
    required this.reverseGeocoder,
  });

  factory AppDependencies(
    SharedPreferences preferences, {
    AppConfig config = const AppConfig(),
    LocationService? locationService,
    MediaPickerService? mediaPicker,
    ReverseGeocoder? reverseGeocoder,
    DateTime Function()? clock,
    @visibleForTesting AuthRepository? authRepository,
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
      mode: BackendMode(live: authRepository != null),
      authRepository: authRepository,
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
      reverseGeocoder: reverseGeocoder ?? NominatimReverseGeocoder(),
    );
  }

  factory AppDependencies.live(
    SharedPreferences preferences,
    SupabaseClient client, {
    AppConfig config = const AppConfig(),
    LocationService? locationService,
    MediaPickerService? mediaPicker,
    ReverseGeocoder? reverseGeocoder,
  }) {
    final db = SupabaseDbGateway(client);
    final media = SupabaseMediaStore(client);
    final auth = SupabaseAuthRepository(
        client, db, ContractorApplications(db, preferences));
    final complaints = SupabaseComplaintRepository(db, media);
    final jobs = SupabaseJobRepository(db, media);
    final contractors = SupabaseContractorRepository(db);
    final notifications = SupabaseNotificationRepository(db);
    final rules = SupabasePriorityRulesRepository(db,
        municipalityId: () => auth.currentProfile?.municipalityId);
    final complaintService = SupabaseComplaintService(
      complaints: complaints,
      rules: rules,
      contractors: contractors,
      notifications: notifications,
      jobs: jobs,
      db: db,
      media: media,
      profile: () => auth.currentProfile,
    );
    Future<void> refreshAll() async {
      await Future.wait([
        complaints.refresh(),
        jobs.refresh(),
        contractors.refresh(),
        notifications.refresh(),
        rules.refresh(),
      ]);
    }

    void clearAll() {
      complaints.clear();
      jobs.clear();
      contractors.clear();
      notifications.clear();
      rules.clear();
    }

    auth.onProfileReady = (_) => rules.refresh().catchError((Object _) {});
    final sync = LiveSync(client, refreshAll: refreshAll, clearAll: clearAll)
      ..start();

    return AppDependencies._(
      mode: const BackendMode(live: true),
      authRepository: auth,
      liveSync: sync,
      config: config,
      sessionRepository: LocalSessionRepository(preferences),
      complaintRepository: complaints,
      jobRepository: jobs,
      contractorRepository: contractors,
      notificationRepository: notifications,
      priorityRulesRepository: rules,
      complaintService: complaintService,
      jobService: SupabaseJobService(
        jobs: jobs,
        contractors: contractors,
        complaintRepository: complaints,
        complaints: complaintService,
        notifications: notifications,
        db: db,
        media: media,
      ),
      locationService: locationService ?? const GeolocatorLocationService(),
      mediaPicker: mediaPicker ?? ImagePickerMediaService(),
      reverseGeocoder: reverseGeocoder ?? NominatimReverseGeocoder(),
    );
  }

  final BackendMode mode;

  final AuthRepository? authRepository;
  final LiveSync? liveSync;
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

  final ReverseGeocoder reverseGeocoder;
}
