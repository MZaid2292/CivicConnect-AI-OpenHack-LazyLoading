import 'dart:convert';

import 'package:civicconnect_ai/core/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(String role) {
  String part(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'role': role})}.signature';
}

void main() {
  const url = 'https://voevsiytapwqqlrdwexd.supabase.co';

  test('missing values keep the app on local repositories', () {
    expect(SupabaseConfig.tryCreate(url: '', anonKey: ''), isNull);
    expect(SupabaseConfig.tryCreate(url: url, anonKey: ' '), isNull);
    expect(SupabaseConfig.fromEnvironment(), isNull,
        reason: 'tests run without dart-defines');
  });

  test('anon and publishable keys are accepted', () {
    expect(
        SupabaseConfig.tryCreate(url: url, anonKey: _jwt('anon')), isNotNull);
    expect(SupabaseConfig.tryCreate(url: url, anonKey: 'sb_publishable_abc123'),
        isNotNull);
  });

  test('service_role and secret keys are refused', () {
    expect(
        () => SupabaseConfig.tryCreate(url: url, anonKey: _jwt('service_role')),
        throwsStateError);
    expect(() => SupabaseConfig.tryCreate(url: url, anonKey: 'sb_secret_xyz'),
        throwsStateError);
  });

  test('non-https URLs are refused', () {
    expect(
        () => SupabaseConfig.tryCreate(
            url: 'http://example.com', anonKey: _jwt('anon')),
        throwsStateError);
  });
}
