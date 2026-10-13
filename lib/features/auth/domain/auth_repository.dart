import 'package:equatable/equatable.dart';

import '../../../core/models/app_role.dart';
import '../../jobs/domain/contractor.dart';

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

  final String dbRole;

  final AppRole? role;
  final String? municipalityId;
  final String? municipalityName;

  final String? contractorId;
  final ContractorStatus? contractorStatus;

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

class MunicipalityOption extends Equatable {
  const MunicipalityOption({required this.id, required this.name});
  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

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
  submitted,

  confirmEmailFirst,
}

class SignUpResult {
  const SignUpResult({this.profile, this.needsEmailConfirmation = false});
  final UserProfile? profile;
  final bool needsEmailConfirmation;
}

abstract class AuthRepository {
  Stream<AuthEvent> get events;
  UserProfile? get currentProfile;

  Future<UserProfile?> restore();
  Future<UserProfile> signIn(String email, String password);

  Future<SignUpResult> signUp(String name, String email, String password);

  Future<List<MunicipalityOption>> listMunicipalities();

  Future<ContractorSignUpOutcome> signUpContractor(String name, String email,
      String password, ContractorApplication application);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
}
