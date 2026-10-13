import 'dart:async';
import 'dart:typed_data';

import 'package:civicconnect_ai/core/models/app_role.dart';
import 'package:civicconnect_ai/core/models/workflow_exception.dart';
import 'package:civicconnect_ai/core/supabase/db_gateway.dart';
import 'package:civicconnect_ai/core/supabase/media_store.dart';
import 'package:civicconnect_ai/features/auth/domain/auth_repository.dart';
import 'package:civicconnect_ai/features/jobs/domain/contractor.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// In-memory stand-in for PostgREST: tables of rows, eq/in filters, ordering,
/// column defaults for inserts, recorded RPC calls and injectable failures.
class FakeDb implements DbGateway {
  FakeDb({this.currentUserId, Map<String, List<Row>>? tables})
      : tables = tables ?? {};

  @override
  String? currentUserId;
  final Map<String, List<Row>> tables;
  final calls = <String>[];
  final allRpcCalls = <(String, Map<String, Object?>)>[];

  /// Workflow RPCs (excludes the read-only display-name lookup).
  List<(String, Map<String, Object?>)> get rpcCalls => [
        for (final c in allRpcCalls)
          if (c.$1 != 'get_display_names') c
      ];

  /// RPC implementations; unknown functions fail like a missing function.
  final rpcHandlers =
      <String, FutureOr<dynamic> Function(Map<String, Object?> params)>{};

  /// Throws for an insert into a table when set.
  WorkflowException? Function(String table, Map<String, Object?> values)?
      failInsert;

  List<Row> table(String name) => tables.putIfAbsent(name, () => []);

  @override
  Future<List<Row>> select(String t,
      {String columns = '*',
      Map<String, Object> eq = const {},
      String? inColumn,
      List<Object>? inValues,
      String? orderBy,
      bool ascending = false,
      int? limit}) async {
    calls.add('select:$t');
    var rows = table(t).where((r) {
      for (final e in eq.entries) {
        if (r[e.key] != e.value) return false;
      }
      if (inColumn != null && !(inValues ?? []).contains(r[inColumn])) {
        return false;
      }
      return true;
    }).toList();
    if (orderBy != null) {
      rows.sort((a, b) {
        final c = '${a[orderBy]}'.compareTo('${b[orderBy]}');
        return ascending ? c : -c;
      });
    }
    if (limit != null && rows.length > limit) rows = rows.sublist(0, limit);
    return [for (final r in rows) Map.of(r)];
  }

  @override
  Future<Row> insert(String t, Map<String, Object?> values) async {
    calls.add('insert:$t');
    final error = failInsert?.call(t, values);
    if (error != null) throw error;
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      ...values,
    };
    if (t == 'complaints') {
      row.putIfAbsent('reference_code',
          () => 'CMP-${(row['id'] as String).substring(0, 8).toUpperCase()}');
      row.putIfAbsent('status', () => 'submitted');
      row.putIfAbsent('priority', () => 'medium');
      row.putIfAbsent('priority_score', () => 30);
      row.putIfAbsent('suggested_category', () => values['category']);
      row.putIfAbsent('classification_method', () => 'keyword_rules');
    }
    table(t).add(row);
    return Map.of(row);
  }

  @override
  Future<void> delete(String t, Map<String, Object> match) async {
    calls.add('delete:$t');
    table(t)
        .removeWhere((r) => match.entries.every((e) => r[e.key] == e.value));
  }

  @override
  Future<void> update(
      String t, Map<String, Object?> values, Map<String, Object> match,
      {String? isNull}) async {
    calls.add('update:$t');
    for (final r in table(t)) {
      if (match.entries.every((e) => r[e.key] == e.value) &&
          (isNull == null || r[isNull] == null)) {
        r.addAll(values);
      }
    }
  }

  @override
  Future<dynamic> rpc(String function, [Map<String, Object?>? params]) async {
    calls.add('rpc:$function');
    allRpcCalls.add((function, params ?? const {}));
    final handler = rpcHandlers[function];
    if (handler == null) {
      throw const WorkflowException(
          'This action needs a database update that has not been applied '
          'yet.');
    }
    return handler(params ?? const {});
  }
}

class FakeMediaStore implements MediaStore {
  final uploads = <(String bucket, String path, String mime)>[];

  /// Upload attempts with these indexes (0-based) fail.
  Set<int> failAt = {};
  int _attempt = 0;

  @override
  Future<void> upload(String bucket, String path, Uint8List bytes,
      {required String contentType}) async {
    final i = _attempt++;
    if (failAt.contains(i)) {
      throw const WorkflowException('Photo upload failed: network');
    }
    uploads.add((bucket, path, contentType));
  }

  @override
  Future<Map<String, String>> signedUrls(
          String bucket, List<String> paths) async =>
      {for (final p in paths) p: 'https://signed.example/$bucket/$p?token=t'};
}

/// Scriptable [AuthRepository] for session and routing tests.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(
      {this.persisted, Map<String, (String, UserProfile)>? accounts})
      : accounts = accounts ?? {};

  /// Profile restored from a persisted session at startup.
  UserProfile? persisted;

  /// email → (password, profile)
  final Map<String, (String, UserProfile)> accounts;
  final _events = StreamController<AuthEvent>.broadcast();
  UserProfile? _current;
  final resetRequests = <String>[];
  String? updatedPassword;
  bool confirmEmailOnSignUp = false;

  List<MunicipalityOption> municipalities = const [
    MunicipalityOption(id: 'muni-1', name: 'Karachi Metropolitan'),
  ];

  /// Server-side applications by email (mirrors `contractors`).
  final applications = <String, ContractorApplication>{};

  /// Kept "on device" until the email is confirmed (no password).
  final pendingLocal = <String, ContractorApplication>{};

  void emit(AuthEvent e) => _events.add(e);

  @override
  Stream<AuthEvent> get events => _events.stream;

  @override
  UserProfile? get currentProfile => _current;

  @override
  Future<UserProfile?> restore() async => _current = persisted;

  @override
  Future<UserProfile> signIn(String email, String password) async {
    final account = accounts[email.trim()];
    if (account == null || account.$1 != password) {
      throw const WorkflowException('Incorrect email or password.');
    }
    final local = pendingLocal.remove(email.trim());
    if (local != null) {
      _apply(email.trim(), local);
      // Like the real repository: reload the profile after submitting.
      return _current = persisted = accounts[email.trim()]!.$2;
    }
    if (account.$2.role == null) {
      throw const WorkflowException('This account has no dashboard.');
    }
    return _current = persisted = account.$2;
  }

  @override
  Future<SignUpResult> signUp(
      String name, String email, String password) async {
    if (confirmEmailOnSignUp) {
      return const SignUpResult(needsEmailConfirmation: true);
    }
    final profile = citizenProfile(name: name, email: email);
    accounts[email] = (password, profile);
    return SignUpResult(profile: _current = persisted = profile);
  }

  @override
  Future<List<MunicipalityOption>> listMunicipalities() async => municipalities;

  @override
  Future<ContractorSignUpOutcome> signUpContractor(String name, String email,
      String password, ContractorApplication application) async {
    accounts[email] = (password, citizenProfile(name: name, email: email));
    if (confirmEmailOnSignUp) {
      pendingLocal[email] = application;
      return ContractorSignUpOutcome.confirmEmailFirst;
    }
    _apply(email, application);
    return ContractorSignUpOutcome.submitted;
  }

  /// Creates the pending application (role stays citizen); duplicates are
  /// ignored like the UNIQUE(owner_id) constraint.
  void _apply(String email, ContractorApplication application) {
    if (applications.containsKey(email)) return;
    applications[email] = application;
    final (password, p) = accounts[email]!;
    accounts[email] = (
      password,
      UserProfile(
        userId: p.userId,
        email: p.email,
        displayName: p.displayName,
        dbRole: p.dbRole,
        role: p.role,
        municipalityId: p.municipalityId,
        municipalityName: p.municipalityName,
        contractorId: 'contractor-$email',
        contractorStatus: ContractorStatus.pendingApproval,
      ),
    );
  }

  /// Simulates verify_contractor(approved|rejected) by a municipal admin.
  void decide(String email, {required bool approve}) {
    final (password, p) = accounts[email]!;
    accounts[email] = (
      password,
      UserProfile(
        userId: p.userId,
        email: p.email,
        displayName: p.displayName,
        dbRole: approve ? 'contractor' : p.dbRole,
        role: approve ? AppRole.contractor : p.role,
        municipalityId: applications[email]?.municipalityId,
        municipalityName: p.municipalityName,
        contractorId: p.contractorId,
        contractorStatus:
            approve ? ContractorStatus.approved : ContractorStatus.rejected,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _current = persisted = null;
  }

  @override
  Future<void> sendPasswordReset(String email) async =>
      resetRequests.add(email);

  @override
  Future<void> updatePassword(String newPassword) async =>
      updatedPassword = newPassword;
}

UserProfile citizenProfile(
        {String name = 'Sana Iqbal', String email = 'sana@example.com'}) =>
    UserProfile(
      userId: 'user-citizen-1',
      email: email,
      displayName: name,
      dbRole: 'citizen',
      role: AppRole.citizen,
      municipalityId: 'muni-1',
      municipalityName: 'Karachi Metropolitan',
    );
