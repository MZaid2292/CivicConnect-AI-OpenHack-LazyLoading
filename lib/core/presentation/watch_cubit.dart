import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum LoadStatus { loading, ready, failure }

class DataState<T> extends Equatable {
  const DataState._(this.status, this.data, this.error);
  const DataState.loading() : this._(LoadStatus.loading, null, null);
  const DataState.ready(T data) : this._(LoadStatus.ready, data, null);
  const DataState.failure(String error)
      : this._(LoadStatus.failure, null, error);

  final LoadStatus status;
  final T? data;
  final String? error;

  @override
  List<Object?> get props => [status, data, error];
}

class WatchCubit<T> extends Cubit<DataState<T>> {
  WatchCubit(this._source) : super(const DataState.loading()) {
    _listen();
  }

  final Stream<T> Function() _source;
  StreamSubscription<T>? _sub;

  void _listen() {
    _sub?.cancel();
    _sub = _source().listen(
      (data) => emit(DataState.ready(data)),
      onError: (Object e) => emit(DataState.failure(e.toString())),
    );
  }

  void retry() {
    emit(const DataState.loading());
    _listen();
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
