import 'services/priority_engine.dart';

abstract class PriorityRulesRepository {
  PriorityRules get current;
  Stream<PriorityRules> watch();
  Future<void> save(PriorityRules rules);
}
