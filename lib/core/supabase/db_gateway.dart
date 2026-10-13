import 'package:supabase_flutter/supabase_flutter.dart';

import 'db_errors.dart';

typedef Row = Map<String, dynamic>;

abstract class DbGateway {
  String? get currentUserId;

  Future<List<Row>> select(
    String table, {
    String columns = '*',
    Map<String, Object> eq = const {},
    String? inColumn,
    List<Object>? inValues,
    String? orderBy,
    bool ascending = false,
    int? limit,
  });

  Future<Row> insert(String table, Map<String, Object?> values);

  Future<void> delete(String table, Map<String, Object> match);

  Future<void> update(
      String table, Map<String, Object?> values, Map<String, Object> match,
      {String? isNull});

  Future<dynamic> rpc(String function, [Map<String, Object?> params]);
}

class SupabaseDbGateway implements DbGateway {
  SupabaseDbGateway(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Row>> select(
    String table, {
    String columns = '*',
    Map<String, Object> eq = const {},
    String? inColumn,
    List<Object>? inValues,
    String? orderBy,
    bool ascending = false,
    int? limit,
  }) =>
      guardDb(() async {
        var query = _client.from(table).select(columns);
        for (final e in eq.entries) {
          query = query.eq(e.key, e.value);
        }
        if (inColumn != null && inValues != null) {
          query = query.inFilter(inColumn, inValues);
        }
        PostgrestTransformBuilder<List<Row>> q = query;
        if (orderBy != null) q = q.order(orderBy, ascending: ascending);
        if (limit != null) q = q.limit(limit);
        return await q;
      });

  @override
  Future<Row> insert(String table, Map<String, Object?> values) =>
      guardDb(() => _client.from(table).insert(values).select().single());

  @override
  Future<void> delete(String table, Map<String, Object> match) =>
      guardDb(() => _client.from(table).delete().match(match));

  @override
  Future<void> update(
          String table, Map<String, Object?> values, Map<String, Object> match,
          {String? isNull}) =>
      guardDb(() async {
        var q = _client.from(table).update(values).match(match);
        if (isNull != null) q = q.isFilter(isNull, null);
        await q;
      });

  @override
  Future<dynamic> rpc(String function, [Map<String, Object?>? params]) =>
      guardDb(() => _client.rpc(function, params: params));
}
