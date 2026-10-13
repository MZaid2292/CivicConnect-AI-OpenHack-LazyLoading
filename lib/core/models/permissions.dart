import 'app_role.dart';
import 'workflow_exception.dart';

void requireRole(Actor actor, Set<AppRole> allowed, String action) {
  if (!allowed.contains(actor.role)) {
    throw WorkflowException('${actor.role.label} cannot $action.');
  }
}
