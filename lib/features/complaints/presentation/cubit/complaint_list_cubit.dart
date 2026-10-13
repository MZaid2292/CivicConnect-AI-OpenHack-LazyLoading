import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/utils/text_similarity.dart';
import '../../domain/complaint.dart';
import '../../domain/complaint_repository.dart';

enum ComplaintSort { newest, priority, support }

extension ComplaintSortLabel on ComplaintSort {
  String get label => switch (this) {
        ComplaintSort.newest => 'Newest',
        ComplaintSort.priority => 'Priority',
        ComplaintSort.support => 'Most supported',
      };
}

class ComplaintListState extends Equatable {
  const ComplaintListState({
    this.status = LoadStatus.loading,
    this.all = const [],
    this.query = '',
    this.category,
    this.statuses = const {},
    this.sort = ComplaintSort.newest,
    this.error,
  });

  final LoadStatus status;
  final List<Complaint> all;
  final String query;
  final ComplaintCategory? category;

  final Set<ComplaintStatus> statuses;
  final ComplaintSort sort;
  final String? error;

  List<Complaint> get visible {
    final q = normalizeText(query);
    final items = all.where((c) {
      if (category != null && c.category != category) return false;
      if (statuses.isNotEmpty && !statuses.contains(c.status)) return false;
      if (q.isEmpty) return true;
      return normalizeText('${c.id} ${c.title} ${c.address} ${c.description}')
          .contains(q);
    }).toList();
    switch (sort) {
      case ComplaintSort.newest:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ComplaintSort.priority:
        items.sort((a, b) => b.priority.score.compareTo(a.priority.score));
      case ComplaintSort.support:
        items.sort((a, b) => b.supportCount.compareTo(a.supportCount));
    }
    return items;
  }

  bool get hasFilters =>
      query.isNotEmpty || category != null || statuses.isNotEmpty;

  ComplaintListState copyWith({
    LoadStatus? status,
    List<Complaint>? all,
    String? query,
    ComplaintCategory? category,
    bool clearCategory = false,
    Set<ComplaintStatus>? statuses,
    ComplaintSort? sort,
    String? error,
  }) =>
      ComplaintListState(
        status: status ?? this.status,
        all: all ?? this.all,
        query: query ?? this.query,
        category: clearCategory ? null : (category ?? this.category),
        statuses: statuses ?? this.statuses,
        sort: sort ?? this.sort,
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, all, query, category, statuses, sort, error];
}

class ComplaintListCubit extends Cubit<ComplaintListState> {
  ComplaintListCubit(
    this._repository, {
    bool Function(Complaint)? scope,
    ComplaintSort sort = ComplaintSort.newest,
    Set<ComplaintStatus> statuses = const {},
  })  : _scope = scope ?? ((c) => c.status.isPublic),
        super(ComplaintListState(sort: sort, statuses: statuses)) {
    _listen();
  }

  final ComplaintRepository _repository;
  final bool Function(Complaint) _scope;
  StreamSubscription<List<Complaint>>? _sub;

  void _listen() {
    _sub?.cancel();
    _sub = _repository.watchAll().listen(
          (items) => emit(state.copyWith(
              status: LoadStatus.ready, all: items.where(_scope).toList())),
          onError: (Object e) => emit(
              state.copyWith(status: LoadStatus.failure, error: e.toString())),
        );
  }

  void retry() {
    emit(state.copyWith(status: LoadStatus.loading));
    _listen();
  }

  void search(String query) => emit(state.copyWith(query: query));
  void setCategory(ComplaintCategory? category) => emit(category == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(category: category));
  void setStatuses(Set<ComplaintStatus> statuses) =>
      emit(state.copyWith(statuses: statuses));
  void setSort(ComplaintSort sort) => emit(state.copyWith(sort: sort));
  void clearFilters() =>
      emit(state.copyWith(query: '', clearCategory: true, statuses: const {}));

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
