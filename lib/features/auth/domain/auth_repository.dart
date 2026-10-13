import 'package:equatable/equatable.dart';

import '../../../core/models/app_role.dart';
import '../../jobs/domain/contractor.dart';

/// The signed-in account as stored in the database. [role] comes only from
/// the protected `profiles.role` column — never from the client.
class UserProfile extends Equatable {
  const UserProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.dbRole,
    required this.role,
    this.municipalityId,
    this.municipalityName,
    this.contractorId,
    this.contractorStatus,
  });

  final String userId;
  final String email;
  final String displayName;

  /// Raw database role: citizen | contractor | municipal_admin | inspector |
  /// finance.
  final String dbRole;

  /// Dashboard for this account; null for roles without one in the app.
  final AppRole? role;
  final String? municipalityId;
  final String? municipalityName;

  /// The `contractors` row owned by this account, if any.
  final String? contractorId;
  final ContractorStatus? contractorStatus;

  /// Identity used by the domain layer. Contractor dashboards key work by the
  /// contractor record, everyone else by their auth id.
  Actor get actor => Actor(
        id: role == AppRole.contractor && contractorId != null
            ? contractorId!
            : userId,
        name: displayName,
        role: role ?? AppRole.citizen,
      );

  @override
  List<Object?> get props => [
        userId,
        email,
        displayName,
        dbRole,
        role,
        municipalityId,
        municipalityName,
        contractorId,
        contractorStatus,
      ];
}

enum AuthEvent { signedIn, signedOut, passwordRecovery }

/// Result of a sign-up: either signed in, or waiting for email confirmation.
class SignUpResult {
  const SignUpResult({this.profile, this.needsEmailConfirmation = false});
  final UserProfile? profile;
  final bool needsEmailConfirmation;
}

/// Real authentication (Supabase Auth). Errors are WorkflowExceptions with
/// user-facing messages.
abstract class AuthRepository {
  Stream<AuthEvent> get events;
  UserProfile? get currentProfile;

  /// Loads the profile for a persisted session; null when signed out.
  Future<UserProfile?> restore();
  Future<UserProfile> signIn(String email, String password);

  /// Public sign-up always creates a citizen account (database default).
  Future<SignUpResult> signUp(String name, String email, String password);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
}
