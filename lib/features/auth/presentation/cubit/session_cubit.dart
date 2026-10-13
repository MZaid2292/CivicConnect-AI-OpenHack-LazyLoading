import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/app_role.dart';
import '../../domain/session_repository.dart';

class SessionState extends Equatable {
  const SessionState(
      {this.role, this.loading = true, this.onboardingSeen = false});
  final AppRole? role;
  final bool loading;
  final bool onboardingSeen;

  /// The fixed demo identity for the selected role (not authenticated).
  Actor? get actor => role == null ? null : Actor.demoFor(role!);

  @override
  List<Object?> get props => [role, loading, onboardingSeen];
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._repository) : super(const SessionState());
  final SessionRepository _repository;

  Future<void> restoreSession() async {
    final role = await _repository.restoreRole();
    final seen = await _repository.hasSeenOnboarding();
    emit(SessionState(role: role, loading: false, onboardingSeen: seen));
  }

  Future<void> completeOnboarding() async {
    await _repository.markOnboardingSeen();
    emit(SessionState(role: state.role, loading: false, onboardingSeen: true));
  }

  Future<void> enterDemo(AppRole role) async {
    await _repository.saveDemoRole(role);
    await _repository.markOnboardingSeen();
    emit(SessionState(role: role, loading: false, onboardingSeen: true));
  }

  /// Clears the saved demo role. In-memory demo data is kept so you can
  /// switch roles and continue the same workflow.
  Future<void> logout() async {
    await _repository.clearSession();
    emit(SessionState(loading: false, onboardingSeen: state.onboardingSeen));
  }
}
