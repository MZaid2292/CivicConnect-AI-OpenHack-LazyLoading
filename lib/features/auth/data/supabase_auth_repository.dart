import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_codec.dart';
import '../../../core/supabase/db_errors.dart';
import '../../../core/supabase/db_gateway.dart';
import '../domain/auth_repository.dart';

/// Supabase Auth + the trusted `profiles` row. The session is persisted by
/// supabase_flutter (secure local storage on Android, browser storage on web)
/// and refreshed automatically.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, this._db, {String? redirectUrl})
      : _redirectUrl = redirectUrl ?? defaultRedirectUrl() {
    _sub = _client.auth.onAuthStateChange.listen((s) {
      switch (s.event) {
        case AuthChangeEvent.passwordRecovery:
          _events.add(AuthEvent.passwordRecovery);
        case AuthChangeEvent.signedOut:
          _profile = null;
          _events.add(AuthEvent.signedOut);
        case AuthChangeEvent.signedIn:
          _events.add(AuthEvent.signedIn);
        default:
          break;
      }
    });
  }

  final SupabaseClient _client;
  final DbGateway _db;
  final String _redirectUrl;
  final _events = StreamController<AuthEvent>.broadcast();
  StreamSubscription<AuthState>? _sub;
  UserProfile? _profile;

  /// Awaited after a profile loads (e.g. to fetch municipality rules before
  /// the dashboard builds).
  Future<void> Function(UserProfile profile)? onProfileReady;

  /// Where email links (confirmation, password reset) return to. Add this URL
  /// to Supabase → Authentication → URL Configuration → Redirect URLs.
  static String defaultRedirectUrl() =>
      kIsWeb ? Uri.base.origin : 'io.supabase.civicconnect://login-callback/';

  @override
  Stream<AuthEvent> get events => _events.stream;

  @override
  UserProfile? get currentProfile => _profile;

  @override
  Future<UserProfile?> restore() async {
    if (_client.auth.currentSession == null) return null;
    return _profile = await _loadProfile();
  }

  @override
  Future<UserProfile> signIn(String email, String password) async {
    try {
      await _client.auth
          .signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw authError(e);
    } catch (e) {
      throw translateDbError(e);
    }
    return _profile = await _loadProfile();
  }

  @override
  Future<SignUpResult> signUp(
      String name, String email, String password) async {
    final AuthResponse response;
    try {
      // Only a display name is sent. The role is never client-supplied: the
      // database creates the profile as a citizen.
      response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': name.trim()},
        emailRedirectTo: _redirectUrl,
      );
    } on AuthException catch (e) {
      throw authError(e);
    } catch (e) {
      throw translateDbError(e);
    }
    if (response.session == null) {
      return const SignUpResult(needsEmailConfirmation: true);
    }
    return SignUpResult(profile: _profile = await _loadProfile());
  }

  @override
  Future<void> signOut() async {
    _profile = null;
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Local session is cleared even if the network call fails.
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth
          .resetPasswordForEmail(email.trim(), redirectTo: _redirectUrl);
    } on AuthException catch (e) {
      throw authError(e);
    } catch (e) {
      throw translateDbError(e);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    if (newPassword.length < 8) {
      throw const WorkflowException('Use at least 8 characters.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw authError(e);
    } catch (e) {
      throw translateDbError(e);
    }
  }

  Future<UserProfile> _loadProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const WorkflowException('You are signed out. Sign in again.');
    }
    final profile = await loadProfile(_db, user.id, user.email ?? '');
    if (profile.role == null) {
      await signOut();
      throw WorkflowException(
          'This ${profile.dbRole.replaceAll('_', ' ')} account has no '
          'dashboard in this app yet. Use a citizen, contractor or municipal '
          'admin account.');
    }
    _profile = profile;
    await onProfileReady?.call(profile);
    return profile;
  }

  /// Reads the trusted profile, municipality and (for contractors and
  /// applicants) the owned contractor record.
  static Future<UserProfile> loadProfile(
      DbGateway db, String userId, String email) async {
    final rows = await db.select('profiles', eq: {'id': userId}, limit: 1);
    if (rows.isEmpty) {
      throw const WorkflowException(
          'Your profile is still being created. Try signing in again in a '
          'moment.');
    }
    final p = rows.first;
    final municipalityId = p['municipality_id'] as String?;
    String? municipalityName;
    if (municipalityId != null) {
      final m = await db.select('municipalities',
          columns: 'name', eq: {'id': municipalityId}, limit: 1);
      if (m.isNotEmpty) municipalityName = m.first['name'] as String?;
    }
    final contractor = await db.select('contractors',
        columns: 'id, verification_status', eq: {'owner_id': userId}, limit: 1);
    final dbRole = p['role'] as String? ?? 'citizen';
    return UserProfile(
      userId: userId,
      email: email,
      displayName: (p['display_name'] as String?)?.trim().isNotEmpty == true
          ? p['display_name'] as String
          : (email.isEmpty ? 'Citizen' : email.split('@').first),
      dbRole: dbRole,
      role: DbCodec.roleFrom(dbRole),
      municipalityId: municipalityId,
      municipalityName: municipalityName,
      contractorId:
          contractor.isEmpty ? null : contractor.first['id'] as String?,
      contractorStatus: contractor.isEmpty
          ? null
          : DbCodec.contractorStatusFrom(
              contractor.first['verification_status'] as String?),
    );
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
