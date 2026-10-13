class WorkflowException implements Exception {
  const WorkflowException(this.message);
  final String message;

  @override
  String toString() => message;
}
