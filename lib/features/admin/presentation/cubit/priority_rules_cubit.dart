import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/app_role.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/complaint_repository.dart';
import '../../../complaints/domain/services/complaint_service.dart';
import '../../../complaints/domain/services/priority_engine.dart';

class PriorityRulesState extends Equatable {
  const PriorityRulesState({
    required this.saved,
    required this.draft,
    this.openComplaints = const [],
    this.saving = false,
    this.message,
    this.error,
    this.eventId = 0,
  });

  final PriorityRules saved;
  final PriorityRules draft;
  final List<Complaint> openComplaints;
  final bool saving;
  final String? message;
  final String? error;
  final int eventId;

  bool get dirty => saved != draft;

  PriorityRulesState copyWith({
    PriorityRules? saved,
    PriorityRules? draft,
    List<Complaint>? openComplaints,
    bool? saving,
    String? message,
    String? error,
    int? eventId,
  }) =>
      PriorityRulesState(
        saved: saved ?? this.saved,
        draft: draft ?? this.draft,
        openComplaints: openComplaints ?? this.openComplaints,
        saving: saving ?? this.saving,
        message: message,
        error: error,
        eventId: eventId ?? this.eventId,
      );

  @override
  List<Object?> get props =>
      [saved, draft, openComplaints, saving, message, error, eventId];
}

/// Edits a draft copy of the rules with a live preview of how open reports
/// would be re-ranked, then saves through the domain service.
class PriorityRulesCubit extends Cubit<PriorityRulesState> {
  PriorityRulesCubit({
    required ComplaintService service,
    required ComplaintRepository complaints,
    required this.actor,
  })  : _service = service,
        super(PriorityRulesState(saved: service.rules, draft: service.rules)) {
    _sub = complaints.watchAll().listen((all) => emit(state.copyWith(
        openComplaints: all.where((c) => c.status.isOpen).toList())));
  }

  final ComplaintService _service;
  final Actor actor;
  final _engine = const PriorityEngine();
  StreamSubscription<List<Complaint>>? _sub;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }

  /// (complaint, current level, level under draft rules)
  List<(Complaint, PriorityAssessment, PriorityAssessment)> preview() => [
        for (final c in state.openComplaints)
          (
            c,
            _engine.assessComplaint(c, state.saved, _service.now),
            _engine.assessComplaint(c, state.draft, _service.now),
          )
      ]..sort((a, b) => b.$3.score.compareTo(a.$3.score));

  void setCategoryBase(ComplaintCategory category, int value) =>
      emit(state.copyWith(
          draft: state.draft.copyWith(
              categoryBase: {...state.draft.categoryBase, category: value})));

  void setKeyword(String word, int points) {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return;
    emit(state.copyWith(
        draft: state.draft.copyWith(
            severityKeywords: {...state.draft.severityKeywords, w: points})));
  }

  void removeKeyword(String word) => emit(state.copyWith(
      draft: state.draft.copyWith(
          severityKeywords: {...state.draft.severityKeywords}..remove(word))));

  void update(PriorityRules Function(PriorityRules) change) =>
      emit(state.copyWith(draft: change(state.draft)));

  void reset() => emit(state.copyWith(draft: state.saved));
  void restoreDefaults() => emit(state.copyWith(draft: PriorityRules.defaults));

  Future<void> save() async {
    emit(state.copyWith(saving: true));
    try {
      await _service.updatePriorityRules(actor, state.draft);
      emit(state.copyWith(
          saving: false,
          saved: state.draft,
          message: 'Rules saved. All reports were re-scored.',
          eventId: state.eventId + 1));
    } catch (e) {
      emit(state.copyWith(
          saving: false, error: e.toString(), eventId: state.eventId + 1));
    }
  }
}
