import 'dart:convert';

/// Supabase connection settings, supplied at build time from a local,
/// git-ignored file:
///
///   flutter run --dart-define-from-file=supabase.local.json
///
/// (see `supabase.example.json`). Only the public anon / publishable key may
/// be used in the app; service_role / secret keys are rejected because they
/// bypass Row Level Security.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  /// Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Returns null when either
  /// is missing, in which case the app keeps using its local repositories.
  static SupabaseConfig? fromEnvironment() => tryCreate(
        url: const String.fromEnvironment('SUPABASE_URL'),
        anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

  /// Validates raw values. Throws [StateError] for a privileged key.
  static SupabaseConfig? tryCreate(
      {required String url, required String anonKey}) {
    final u = url.trim();
    final k = anonKey.trim();
    if (u.isEmpty || k.isEmpty) return null;
    final uri = Uri.tryParse(u);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('SUPABASE_URL must be an https URL.');
    }
    if (isPrivilegedKey(k)) {
      throw StateError('A service_role / secret key must never be shipped in '
          'the app. Use the anon or publishable key.');
    }
    return SupabaseConfig(url: u, anonKey: k);
  }

  /// True for new-style secret keys and legacy JWTs whose role is
  /// `service_role`.
  static bool isPrivilegedKey(String key) {
    if (key.startsWith('sb_secret_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return payload is Map && payload['role'] == 'service_role';
    } catch (_) {
      return false;
    }
  }
}
