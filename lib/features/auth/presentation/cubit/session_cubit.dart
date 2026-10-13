import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/models/workflow_exception.dart';
import '../../domain/auth_repository.dart';
import '../../domain/session_repository.dart';

class SessionState extends Equatable {
  const SessionState({
    this.role,
    this.loading = true,
    this.onboardingSeen = false,
    this.live = false,
    this.profile,
    this.recoveringPassword = false,
  });

  final AppRole? role;
  final bool loading;
  final bool onboardingSeen;

  /// True when backed by Supabase Auth (real accounts).
  final bool live;

  /// The signed-in account (live mode only).
  final UserProfile? profile;

  /// The user opened a password-reset link and must choose a new password.
  final bool recoveringPassword;

  /// Live: the authenticated account. Local mode: the fixed demo identity for
  /// the selected role (not authenticated).
  Actor? get actor {
    if (live) return profile?.actor;
    return role == null ? null : Actor.demoFor(role!);
  }

  @override
  List<Object?> get props =>
      [role, loading, onboardingSeen, live, profile, recoveringPassword];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._repository, {AuthRepository? auth})
      : _auth = auth,
        super(SessionState(live: auth != null)) {
    _authSub = _auth?.events.listen(_onAuthEvent);
  }

  final SessionRepository _repository;
  final AuthRepository? _auth;
  StreamSubscription<AuthEvent>? _authSub;

  bool get isLive => _auth != null;

  Future<void> restoreSession() async {
    final seen = await _repository.hasSeenOnboarding();
    if (_auth == null) {
      final role = await _repository.restoreRole();
      emit(SessionState(role: role, loading: false, onboardingSeen: seen));
      return;
    }
    UserProfile? profile;
    try {
      profile = await _auth.restore();
    } catch (_) {
      // Expired session, missing profile or offline: show sign-in.
      profile = null;
    }
    _emitLive(profile, onboardingSeen: seen);
  }

  Future<void> completeOnboarding() async {
    await _repository.markOnboardingSeen();
    emit(_copy(onboardingSeen: true));
  }

  /// Local preview mode only — picking a role is never authorization.
  Future<void> enterDemo(AppRole role) async {
    if (isLive) {
      throw const WorkflowException('Sign in with your account.');
    }
    await _repository.saveDemoRole(role);
    await _repository.markOnboardingSeen();
    emit(SessionState(role: role, loading: false, onboardingSeen: true));
  }

  Future<void> signIn(String email, String password) async {
    final profile = await _requireAuth().signIn(email, password);
    await _repository.markOnboardingSeen();
    _emitLive(profile, onboardingSeen: true);
  }

  /// Returns true when signed in; false when the email must be confirmed.
  Future<bool> signUp(String name, String email, String password) async {
    final result = await _requireAuth().signUp(name, email, password);
    await _repository.markOnboardingSeen();
    if (result.profile == null) return false;
    _emitLive(result.profile, onboardingSeen: true);
    return true;
  }

  Future<void> sendPasswordReset(String email) =>
      _requireAuth().sendPasswordReset(email);

  Future<void> updatePassword(String password) async {
    await _requireAuth().updatePassword(password);
    emit(_copy(recoveringPassword: false));
  }

  /// Local mode: clears the saved demo role (in-memory data is kept).
  /// Live mode: signs out of Supabase Auth.
  Future<void> logout() async {
    if (_auth != null) {
      await _auth.signOut();
      _emitLive(null, onboardingSeen: state.onboardingSeen);
      return;
    }
    await _repository.clearSession();
    emit(SessionState(loading: false, onboardingSeen: state.onboardingSeen));
  }

  Future<void> _onAuthEvent(AuthEvent event) async {
    switch (event) {
      case AuthEvent.signedOut:
        _emitLive(null, onboardingSeen: state.onboardingSeen);
      case AuthEvent.passwordRecovery:
        UserProfile? profile = state.profile;
        try {
          profile ??= await _auth!.restore();
        } catch (_) {}
        _emitLive(profile,
            onboardingSeen: true, recoveringPassword: profile != null);
      case AuthEvent.signedIn:
        // E.g. returning from an email confirmation link.
        if (state.profile == null && !state.loading) {
          try {
            final profile = await _auth!.restore();
            if (profile != null) _emitLive(profile, onboardingSeen: true);
          } catch (_) {}
        }
    }
  }

  void _emitLive(UserProfile? profile,
          {required bool onboardingSeen, bool recoveringPassword = false}) =>
      emit(SessionState(
        live: true,
        loading: false,
        onboardingSeen: onboardingSeen,
        profile: profile,
        role: profile?.role,
        recoveringPassword: recoveringPassword,
      ));

  SessionState _copy({bool? onboardingSeen, bool? recoveringPassword}) =>
      SessionState(
        role: state.role,
        loading: false,
        onboardingSeen: onboardingSeen ?? state.onboardingSeen,
        live: state.live,
        profile: state.profile,
        recoveringPassword: recoveringPassword ?? state.recoveringPassword,
      );

  AuthRepository _requireAuth() {
    final auth = _auth;
    if (auth == null) {
      throw const WorkflowException('Accounts are not available offline.');
    }
    return auth;
  }

  @override
  Future<void> close() async {
    await _authSub?.cancel();
    return super.close();
  }
}
