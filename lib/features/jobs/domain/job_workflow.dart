import '../../../core/models/app_role.dart';
import '../../../core/models/workflow_exception.dart';
import 'work_job.dart';

/// Contract state machine (separate from the complaint state machine).
class JobWorkflow {
  const JobWorkflow._();

  static const _admin = {AppRole.municipalAdmin};
  static const _contractor = {AppRole.contractor};

  static const Map<JobStatus, Map<JobStatus, Set<AppRole>>> transitions = {
    JobStatus.openForBids: {
      JobStatus.awarded: _admin,
      JobStatus.cancelled: _admin,
    },
    JobStatus.awarded: {
      JobStatus.inProgress: _contractor,
      JobStatus.cancelled: _admin,
    },
    JobStatus.inProgress: {JobStatus.completionSubmitted: _contractor},
    JobStatus.completionSubmitted: {
      JobStatus.completed: _admin,
      JobStatus.reworkRequested: _admin,
    },
    JobStatus.reworkRequested: {JobStatus.inProgress: _contractor},
    JobStatus.completed: {},
    JobStatus.cancelled: {},
  };

  static bool isValidTransition(JobStatus from, JobStatus to) =>
      transitions[from]?.containsKey(to) ?? false;

  static void ensure(JobStatus from, JobStatus to, AppRole role) {
    if (!isValidTransition(from, to)) {
      throw WorkflowException(
          'Cannot move a job from "${from.label}" to "${to.label}".');
    }
    if (!(transitions[from]![to]!.contains(role))) {
      throw WorkflowException(
          '${role.label} is not allowed to mark a job "${to.label}".');
    }
  }
}
