import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/app_role.dart';
import '../domain/session_repository.dart';

/// DEMO ONLY. Stores a role preference and an onboarding flag — never
/// credentials, tokens or identity. Once Supabase is added, Supabase Auth must
/// be the session authority and roles must come from protected server data.
class LocalSessionRepository implements SessionRepository {
  LocalSessionRepository(this._preferences);
  final SharedPreferences _preferences;
  static const _roleKey = 'demo_role';
  static const _onboardingKey = 'onboarding_seen';

  @override
  Future<AppRole?> restoreRole() async {
    final saved = _preferences.getString(_roleKey);
    for (final role in AppRole.values) {
      if (role.name == saved) return role;
    }
    return null;
  }

  @override
  Future<void> saveDemoRole(AppRole role) =>
      _preferences.setString(_roleKey, role.name);

  @override
  Future<void> clearSession() => _preferences.remove(_roleKey);

  @override
  Future<bool> hasSeenOnboarding() async =>
      _preferences.getBool(_onboardingKey) ?? false;

  @override
  Future<void> markOnboardingSeen() =>
      _preferences.setBool(_onboardingKey, true);
}
