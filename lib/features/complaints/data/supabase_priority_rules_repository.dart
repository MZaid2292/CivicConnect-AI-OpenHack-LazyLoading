import 'dart:async';

import '../../../core/models/workflow_exception.dart';
import '../../../core/supabase/db_codec.dart';
import '../../../core/supabase/db_gateway.dart';
import '../domain/complaint.dart';
import '../domain/priority_rules_repository.dart';
import '../domain/services/priority_engine.dart';

class SupabasePriorityRulesRepository implements PriorityRulesRepository {
  SupabasePriorityRulesRepository(this._db,
      {required this.municipalityId, PriorityRules? defaults})
      : _defaults = defaults ?? PriorityRules.defaults,
        _current = defaults ?? PriorityRules.defaults;

  final DbGateway _db;

  String? Function() municipalityId;
  final PriorityRules _defaults;
  PriorityRules _current;
  final _changes = StreamController<PriorityRules>.broadcast();

  @override
  PriorityRules get current => _current;

  @override
  Stream<PriorityRules> watch() => Stream.multi((controller) {
        controller.add(_current);
        final sub = _changes.stream.listen(controller.add);
        controller.onCancel = sub.cancel;
        refresh().catchError((Object _) {});
      });

  static PriorityRules fromRows(List<Row> rows, PriorityRules defaults) {
    if (rows.isEmpty) return defaults;
    final base = {...defaults.categoryBase};
    for (final r in rows) {
      base[DbCodec.categoryFrom(r['category'] as String?)] =
          DbCodec.toInt(r['base_score']);
    }
    final first = rows.first;
    return defaults.copyWith(
      categoryBase: base,
      pointsPerDayOpen: DbCodec.toInt(first['age_weight']),
      pointsPerSupporter: DbCodec.toInt(first['support_weight']),
    );
  }

  Future<void> refresh() async {
    final m = municipalityId();
    if (m == null) return;
    final rows = await _db.select('priority_rules', eq: {'municipality_id': m});
    _current = fromRows(rows, _defaults);
    _changes.add(_current);
  }

  void clear() => _current = _defaults;

  @override
  Future<void> save(PriorityRules rules) async {
    final unsupported = rules.severityKeywords != _current.severityKeywords ||
        rules.maxSupportPoints != _current.maxSupportPoints ||
        rules.maxAgePoints != _current.maxAgePoints ||
        rules.mediumThreshold != _current.mediumThreshold ||
        rules.highThreshold != _current.highThreshold ||
        rules.criticalThreshold != _current.criticalThreshold;
    if (unsupported) {
      throw const WorkflowException(
          'The server stores issue-type points and the per-supporter and '
          'per-day weights only. Severity words, caps and level thresholds '
          'cannot be saved yet — discard those changes and save again.');
    }
    for (final category in ComplaintCategory.values) {
      final changed =
          rules.categoryBase[category] != _current.categoryBase[category] ||
              rules.pointsPerDayOpen != _current.pointsPerDayOpen ||
              rules.pointsPerSupporter != _current.pointsPerSupporter;
      if (!changed) continue;
      try {
        await _db.rpc('save_priority_rule', {
          'p_category': DbCodec.category(category),
          'p_base_score': rules.categoryBase[category] ?? 0,
          'p_age_weight': rules.pointsPerDayOpen,
          'p_support_weight': rules.pointsPerSupporter,
        });
      } on WorkflowException catch (e) {
        final drainageUnsupported = category == ComplaintCategory.drainage &&
            e.message.contains('Invalid complaint category');
        if (!drainageUnsupported) rethrow;
        if (rules.categoryBase[category] != _current.categoryBase[category]) {
          throw const WorkflowException(
              'Drainage points need the pending database update.');
        }
      }
    }
    await refresh();
  }
}
