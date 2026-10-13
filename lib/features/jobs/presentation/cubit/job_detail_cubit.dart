import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/models/media_attachment.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/services/media_picker_service.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/complaint_repository.dart';
import '../../domain/job_repositories.dart';
import '../../domain/job_service.dart';
import '../../domain/work_job.dart';

class JobDetailState extends Equatable {
  const JobDetailState({
    this.status = LoadStatus.loading,
    this.job,
    this.complaint,
    this.busy = false,
    this.message,
    this.error,
    this.eventId = 0,
    this.done = false,
  });

  final LoadStatus status;
  final WorkJob? job;
  final Complaint? complaint;
  final bool busy;
  final String? message;
  final String? error;
  final int eventId;

  final bool done;

  JobDetailState copyWith({
    LoadStatus? status,
    WorkJob? job,
    Complaint? complaint,
    bool? busy,
    String? message,
    String? error,
    int? eventId,
    bool? done,
  }) =>
      JobDetailState(
        status: status ?? this.status,
        job: job ?? this.job,
        complaint: complaint ?? this.complaint,
        busy: busy ?? this.busy,
        message: message,
        error: error,
        eventId: eventId ?? this.eventId,
        done: done ?? this.done,
      );

  @override
  List<Object?> get props =>
      [status, job, complaint, busy, message, error, eventId, done];
}

class JobDetailCubit extends Cubit<JobDetailState> {
  JobDetailCubit({
    required this.jobId,
    required this.actor,
    required JobRepository jobs,
    required ComplaintRepository complaints,
    required JobService service,
    required MediaPickerService media,
  })  : _jobs = jobs,
        _complaints = complaints,
        _service = service,
        _media = media,
        super(const JobDetailState()) {
    _jSub = _jobs.watchAll().listen((all) {
      final job = all.where((j) => j.id == jobId).firstOrNull;
      if (job == null) {
        emit(state.copyWith(
            status: LoadStatus.failure, error: 'Job $jobId not found.'));
      } else {
        emit(state.copyWith(
            status: LoadStatus.ready, job: job, complaint: _complaintFor(job)));
      }
    });
    _cSub = _complaints.watchAll().listen((all) {
      _latestComplaints = all;
      final job = state.job;
      if (job != null) emit(state.copyWith(complaint: _complaintFor(job)));
    });
  }

  final String jobId;
  final Actor actor;
  final JobRepository _jobs;
  final ComplaintRepository _complaints;
  final JobService _service;
  final MediaPickerService _media;
  StreamSubscription<List<WorkJob>>? _jSub;
  StreamSubscription<List<Complaint>>? _cSub;
  List<Complaint> _latestComplaints = const [];
  static const _uuid = Uuid();

  Complaint? _complaintFor(WorkJob job) =>
      _latestComplaints.where((c) => c.id == job.complaintId).firstOrNull;

  Future<bool> _run(Future<void> Function() action, String success,
      {bool done = false}) async {
    emit(state.copyWith(busy: true));
    try {
      await action();
      emit(state.copyWith(
          busy: false,
          message: success,
          eventId: state.eventId + 1,
          done: done));
      return true;
    } catch (e) {
      emit(state.copyWith(
          busy: false, error: e.toString(), eventId: state.eventId + 1));
      return false;
    }
  }

  Future<void> award(String bidId) => _run(
      () => _service.awardBid(actor, jobId, bidId),
      'Bid awarded. The contractor has been notified.');

  Future<void> inspect({required bool accept, required String note}) => _run(
      () => _service.inspect(actor, jobId, accept: accept, note: note),
      accept
          ? (_service.inspectionReleasesPayment
              ? 'Work accepted. Report resolved; simulated payment released.'
              : 'Work accepted. Report resolved.')
          : 'Rework requested. The contractor has been notified.',
      done: true);

  Future<void> submitBid(int amount, int days, String note) => _run(
      () => _service.submitBid(actor, jobId,
          amount: amount, days: days, note: note),
      _service.bidsAreMock
          ? 'Bid submitted (mock). The municipality will review it.'
          : 'Bid submitted. The municipality will review it.');

  Future<void> startWork() =>
      _run(() => _service.startWork(actor, jobId), 'Work started.');

  Future<void> logProgress(String note) =>
      _run(() => _service.addProgress(actor, jobId, note), 'Progress logged.');

  Future<void> requestCompletion(String note) => _run(
      () => _service.requestCompletion(actor, jobId, note),
      'Submitted for inspection.');

  Future<void> addEvidence(EvidenceStage stage, MediaSource source) async {
    try {
      final picked = await _media.pickImage(source);
      if (picked == null) return;
      await _run(
          () => _service.addEvidence(
              actor,
              jobId,
              MediaAttachment(
                id: _uuid.v4(),
                storage: MediaStorage.localMemory,
                caption:
                    '${stage == EvidenceStage.after ? 'After' : 'Before'} · ${picked.name}',
                bytes: picked.bytes,
                stage: stage,
              )),
          '${stage == EvidenceStage.after ? 'After' : 'Before'} photo added.');
    } on MediaPickException catch (e) {
      emit(state.copyWith(error: e.message, eventId: state.eventId + 1));
    }
  }

  @override
  Future<void> close() async {
    await _jSub?.cancel();
    await _cSub?.cancel();
    return super.close();
  }
}
