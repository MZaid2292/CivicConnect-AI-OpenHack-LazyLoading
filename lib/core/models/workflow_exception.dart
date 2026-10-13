/// Raised when a domain rule (state transition or role permission) blocks an
/// action. Local mock checks mirror rules that the backend must enforce later;
/// they are NOT a security boundary on their own.
class WorkflowException implements Exception {
  const WorkflowException(this.message);
  final String message;

  @override
  String toString() => message;
}
