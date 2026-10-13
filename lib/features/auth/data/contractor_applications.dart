import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_gateway.dart';
import '../domain/auth_repository.dart';

class ContractorApplications {
  ContractorApplications(this._db, this._prefs);

  final DbGateway _db;
  final SharedPreferences _prefs;
  static const _key = 'pending_contractor_application';

  Future<List<MunicipalityOption>> listMunicipalities() async {
    try {
      final rows = await _db.select('municipalities',
          columns: 'id, name', orderBy: 'name', ascending: true);
      return [
        for (final r in rows)
          MunicipalityOption(id: r['id'] as String, name: r['name'] as String),
      ];
    } on WorkflowException {
      throw const WorkflowException(
          'Municipalities could not be loaded. Try again later.');
    }
  }

  Future<bool> submit(String userId, ContractorApplication app) async {
    final existing = await _db.select('contractors',
        columns: 'id', eq: {'owner_id': userId}, limit: 1);
    if (existing.isNotEmpty) return false;
    try {
      await _db.insert('contractors', {
        'owner_id': userId,
        'business_name': app.businessName.trim(),
        'description': (app.description?.trim().isEmpty ?? true)
            ? null
            : app.description!.trim(),
        'municipality_id': app.municipalityId,
        'verification_status': 'pending',
      });
      return true;
    } on WorkflowException catch (e) {
      if (e.message == 'That has already been recorded.') return false;
      rethrow;
    }
  }

  Future<void> savePending(String email, ContractorApplication app) =>
      _prefs.setString(
          _key,
          jsonEncode({
            'email': email.trim().toLowerCase(),
            'business_name': app.businessName.trim(),
            'description': app.description?.trim(),
            'municipality_id': app.municipalityId,
            'municipality_name': app.municipalityName,
          }));

  ContractorApplication? pendingFor(String email) {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['email'] != email.trim().toLowerCase()) return null;
      return ContractorApplication(
        businessName: m['business_name'] as String,
        municipalityId: m['municipality_id'] as String,
        municipalityName: m['municipality_name'] as String?,
        description: m['description'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> completePending(String userId, String email) async {
    final app = pendingFor(email);
    if (app == null) return false;
    final submitted = await submit(userId, app);
    await _prefs.remove(_key);
    return submitted;
  }
}
