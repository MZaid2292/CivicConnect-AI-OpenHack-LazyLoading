import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/complaint_repository.dart';
import '../../../complaints/domain/services/complaint_service.dart';
import '../../../complaints/domain/services/duplicate_detector.dart';

class DuplicateReviewItem extends Equatable {
  const DuplicateReviewItem(this.complaint, this.matches);
  final Complaint complaint;
  final List<DuplicateCandidate> matches;

  @override
  List<Object?> get props => [complaint, matches];
}

class DuplicateReviewState extends Equatable {
  const DuplicateReviewState(
      {this.status = LoadStatus.loading,
      this.items = const [],
      this.message,
      this.error,
      this.eventId = 0});
  final LoadStatus status;
  final List<DuplicateReviewItem> items;
  final String? message;
  final String? error;
  final int eventId;

  @override
  List<Object?> get props => [status, items, message, error, eventId];
}

class DuplicateReviewCubit extends Cubit<DuplicateReviewState> {
  DuplicateReviewCubit(
      {required ComplaintRepository complaints,
      required ComplaintService service,
      required this.actor})
      : _service = service,
        super(const DuplicateReviewState()) {
    _sub = complaints.watchAll().listen((_) => _refresh());
  }

  final ComplaintService _service;
  final Actor actor;
  StreamSubscription<List<Complaint>>? _sub;

  Future<void> _refresh() async {
    try {
      final queue = await _service.duplicateReviewQueue();
      if (isClosed) return;
      final items = [
        for (final e in queue.entries) DuplicateReviewItem(e.key, e.value)
      ]..sort((a, b) => b.matches.first.score.compareTo(a.matches.first.score));
      emit(DuplicateReviewState(
          status: LoadStatus.ready, items: items, eventId: state.eventId));
    } catch (e) {
      if (!isClosed) {
        emit(DuplicateReviewState(
            status: LoadStatus.failure, error: e.toString()));
      }
    }
  }

  Future<void> _act(Future<void> Function() action, String success) async {
    try {
      await action();
      emit(DuplicateReviewState(
          status: state.status,
          items: state.items,
          message: success,
          eventId: state.eventId + 1));
    } catch (e) {
      emit(DuplicateReviewState(
          status: state.status,
          items: state.items,
          error: e.toString(),
          eventId: state.eventId + 1));
    }
  }

  Future<void> merge(String duplicateId, String originalId) => _act(
      () => _service.markDuplicate(actor, duplicateId, originalId),
      '$duplicateId merged into $originalId.');

  Future<void> keepSeparate(String id) => _act(
      () => _service.clearDuplicateFlag(actor, id),
      '$id marked as a distinct report.');

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
