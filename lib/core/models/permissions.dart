import 'app_role.dart';
import 'workflow_exception.dart';

/// Role checks used by mock domain services.
///
/// These mirror rules the backend must enforce (Supabase RLS / RPC). On the
/// client they only keep the UI honest — they are not a security boundary.
void requireRole(Actor actor, Set<AppRole> allowed, String action) {
  if (!allowed.contains(actor.role)) {
    throw WorkflowException('${actor.role.label} cannot $action.');
  }
}
