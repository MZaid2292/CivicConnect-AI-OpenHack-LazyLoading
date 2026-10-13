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

/// A municipality a contractor can apply to (public id + name only).
class MunicipalityOption extends Equatable {
  const MunicipalityOption({required this.id, required this.name});
  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

/// Contractor self-registration details. Creates a *pending* row in
/// `contractors`; the account stays a citizen until a municipal admin
/// approves it through `verify_contractor`.
class ContractorApplication extends Equatable {
  const ContractorApplication({
    required this.businessName,
    required this.municipalityId,
    this.municipalityName,
    this.description,
  });
  final String businessName;
  final String municipalityId;
  final String? municipalityName;
  final String? description;

  @override
  List<Object?> get props =>
      [businessName, municipalityId, municipalityName, description];
}

enum ContractorSignUpOutcome {
  /// Account created and the pending application stored on the server.
  submitted,

  /// Email confirmation is required first; the application is sent on the
  /// first sign-in after confirming.
  confirmEmailFirst,
}

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

  /// Municipalities open for contractor applications.
  Future<List<MunicipalityOption>> listMunicipalities();

  /// Creates a citizen account plus a pending contractor application. Never
  /// grants contractor access — approval is a municipal decision.
  Future<ContractorSignUpOutcome> signUpContractor(String name, String email,
      String password, ContractorApplication application);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
}
