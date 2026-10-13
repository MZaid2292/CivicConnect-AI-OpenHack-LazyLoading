import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_exception.dart';

/// Runs a backend call and converts failures into [WorkflowException]s with
/// messages the existing UI can show as-is.
Future<T> guardDb<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on WorkflowException {
    rethrow;
  } catch (e) {
    throw translateDbError(e);
  }
}

WorkflowException translateDbError(Object e) {
  if (e is WorkflowException) return e;
  if (e is PostgrestException) return _postgrest(e.code, e.message);
  if (e is StorageException) {
    final m = e.message.toLowerCase();
    if (m.contains('size') || e.statusCode == '413') {
      return const WorkflowException('That photo is too large to upload.');
    }
    if (m.contains('mime') || m.contains('type')) {
      return const WorkflowException(
          'Only JPEG, PNG or WebP photos can be uploaded.');
    }
    if (m.contains('row-level security') || e.statusCode == '403') {
      return const WorkflowException(
          'You are not allowed to upload a photo here.');
    }
    return WorkflowException('Photo upload failed: ${e.message}');
  }
  if (e is AuthException) return authError(e);
  final text = e.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('XMLHttpRequest')) {
    return const WorkflowException(
        'Network problem. Check your connection and try again.');
  }
  return WorkflowException('Something went wrong: $text');
}

WorkflowException _postgrest(String? code, String message) {
  switch (code) {
    // RAISE EXCEPTION inside the workflow functions: already human-readable.
    case 'P0001':
      return WorkflowException(message);
    case '42501':
      return const WorkflowException('You do not have permission to do that.');
    case '23505':
      return const WorkflowException('That has already been recorded.');
    case '23514':
      if (message.contains('category')) {
        return const WorkflowException(
            'This category is not enabled on the server yet.');
      }
      return const WorkflowException('The server rejected one of the values.');
    case '23503':
      return const WorkflowException('A linked record no longer exists.');
    case 'PGRST202':
    case '42883':
      return const WorkflowException(
          'This action needs a database update that has not been applied '
          'yet.');
    case 'PGRST116':
      return const WorkflowException('Record not found.');
  }
  if (message.contains('row-level security')) {
    return const WorkflowException('You do not have permission to do that.');
  }
  return WorkflowException(message);
}

WorkflowException authError(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login credentials')) {
    return const WorkflowException('Incorrect email or password.');
  }
  if (m.contains('email not confirmed')) {
    return const WorkflowException(
        'Confirm your email address first — check your inbox for the link.');
  }
  if (m.contains('already registered') || m.contains('already been')) {
    return const WorkflowException(
        'An account with this email already exists. Sign in instead.');
  }
  if (m.contains('rate limit') || e.statusCode == '429') {
    return const WorkflowException(
        'Too many attempts. Wait a minute and try again.');
  }
  if (m.contains('password')) return WorkflowException(e.message);
  return WorkflowException(e.message);
}
