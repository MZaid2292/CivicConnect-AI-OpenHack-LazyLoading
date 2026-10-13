import '../../../core/models/app_role.dart';
import '../../../core/models/workflow_exception.dart';
import '../../jobs/domain/contractor.dart';
import 'auth_repository.dart';

class RoleAccessException extends WorkflowException {
  const RoleAccessException(super.message, {this.pendingApproval = false});
  final bool pendingApproval;
}

class LoginRoleCheck {
  const LoginRoleCheck._();

  static RoleAccessException? problem(UserProfile profile, AppRole selected) {
    switch (selected) {
      case AppRole.citizen:
        if (profile.role == AppRole.citizen) return null;
        return RoleAccessException(
            'This is a ${_describe(profile)} account. Choose '
            '${profile.role?.label ?? 'the matching role'} to sign in.');

      case AppRole.municipalAdmin:
        if (profile.role != AppRole.municipalAdmin) {
          return RoleAccessException(
              'This account is not a municipal admin account.');
        }
        if (profile.municipalityId == null) {
          return const RoleAccessException(
              'Your admin account has no municipality assigned yet. Contact '
              'your system administrator.');
        }
        return null;

      case AppRole.contractor:
        if (profile.role == AppRole.contractor &&
            profile.contractorStatus == ContractorStatus.approved) {
          return null;
        }
        switch (profile.contractorStatus) {
          case ContractorStatus.pendingApproval:
            return const RoleAccessException(
                'Your contractor application is waiting for approval by the '
                'municipality. You can sign in as a contractor once it is '
                'approved.',
                pendingApproval: true);
          case ContractorStatus.rejected:
            return const RoleAccessException(
                'Your contractor application was not approved. Contact the '
                'municipality for details.');
          case ContractorStatus.suspended:
          case ContractorStatus.approved:
          case null:
            break;
        }
        if (profile.role == AppRole.contractor) {
          return const RoleAccessException(
              'Your contractor record is not approved.');
        }
        return const RoleAccessException(
            'This account is not registered as a contractor. Choose Sign up '
            'to apply.');
    }
  }

  static String _describe(UserProfile p) => switch (p.role) {
        AppRole.municipalAdmin => 'municipal admin',
        AppRole.contractor => 'contractor',
        AppRole.citizen || null => 'citizen',
      };
}
