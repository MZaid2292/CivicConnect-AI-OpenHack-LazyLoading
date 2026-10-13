import '../../../core/models/app_role.dart';

abstract class SessionRepository {
  Future<AppRole?> restoreRole();
  Future<void> saveDemoRole(AppRole role);
  Future<void> clearSession();
  Future<bool> hasSeenOnboarding();
  Future<void> markOnboardingSeen();
}
