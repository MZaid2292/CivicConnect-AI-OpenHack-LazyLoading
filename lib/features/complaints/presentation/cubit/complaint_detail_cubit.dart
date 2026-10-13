import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../jobs/domain/job_repositories.dart';
import '../../../jobs/domain/job_service.dart';
import '../../../jobs/domain/work_job.dart';
import '../../domain/complaint.dart';
import '../../domain/complaint_repository.dart';
import '../../domain/services/complaint_service.dart';
import '../../domain/services/duplicate_detector.dart';

class ComplaintDetailState extends Equatable {
  const ComplaintDetailState({
    this.status = LoadStatus.loading,
    this.complaint,
    this.job,
    this.busy = false,
    this.message,
    this.error,
    this.eventId = 0,
  });

  final LoadStatus status;
  final Complaint? complaint;
  final WorkJob? job;
  final bool busy;

  final String? message;
  final String? error;
  final int eventId;

  ComplaintDetailState copyWith({
    LoadStatus? status,
    Complaint? complaint,
    WorkJob? job,
    bool? busy,
    String? message,
    String? error,
    int? eventId,
  }) =>
      ComplaintDetailState(
        status: status ?? this.status,
        complaint: complaint ?? this.complaint,
        job: job ?? this.job,
        busy: busy ?? this.busy,
        message: message,
        error: error,
        eventId: eventId ?? this.eventId,
      );

  @override
  List<Object?> get props =>
      [status, complaint, job, busy, message, error, eventId];
}

class ComplaintDetailCubit extends Cubit<ComplaintDetailState> {
  ComplaintDetailCubit({
    required this.complaintId,
    required this.actor,
    required ComplaintRepository complaints,
    required JobRepository jobs,
    required ComplaintService complaintService,
    required JobService jobService,
  })  : _complaints = complaints,
        _jobs = jobs,
        _complaintService = complaintService,
        _jobService = jobService,
        super(const ComplaintDetailState()) {
    _listen();
  }

  final String complaintId;
  final Actor actor;
  final ComplaintRepository _complaints;
  final JobRepository _jobs;
  final ComplaintService _complaintService;
  final JobService _jobService;
  StreamSubscription<List<Complaint>>? _cSub;
  StreamSubscription<List<WorkJob>>? _jSub;
  List<WorkJob> _latestJobs = const [];

  void _listen() {
    _cSub = _complaints.watchAll().listen((items) {
      final c = items.where((e) => e.id == complaintId).firstOrNull;
      if (c == null) {
        emit(state.copyWith(
            status: LoadStatus.failure,
            error: 'Report $complaintId not found.'));
        return;
      }
      emit(state.copyWith(
          status: LoadStatus.ready, complaint: c, job: _jobFor(c)));
    }, onError: (Object e) {
      emit(state.copyWith(status: LoadStatus.failure, error: e.toString()));
    });
    _jSub = _jobs.watchAll().listen((jobs) {
      _latestJobs = jobs;
      final c = state.complaint;
      if (c != null) emit(state.copyWith(job: _jobFor(c)));
    });
  }

  WorkJob? _jobFor(Complaint c) =>
      _latestJobs.where((j) => j.id == c.jobId).firstOrNull ??
      _latestJobs.where((j) => j.complaintId == c.id).firstOrNull;

  Future<void> _run(Future<void> Function() action, String success) async {
    emit(state.copyWith(busy: true));
    try {
      await action();
      emit(state.copyWith(
          busy: false, message: success, eventId: state.eventId + 1));
    } catch (e) {
      emit(state.copyWith(
          busy: false, error: e.toString(), eventId: state.eventId + 1));
    }
  }

  Future<void> toggleSupport() {
    final supporting =
        state.complaint?.supporterIds.contains(actor.id) ?? false;
    return _run(() => _complaintService.toggleSupport(actor, complaintId),
        supporting ? 'Support removed.' : 'Thanks! Your support was added.');
  }

  Future<void> addComment(String text) => _run(
      () => _complaintService.addComment(actor, complaintId, text),
      'Comment posted.');

  Future<void> rate(int rating, String comment) => _run(
      () =>
          _complaintService.rateResolution(actor, complaintId, rating, comment),
      'Thanks for rating the work!');

  Future<void> verify(String department, String note) => _run(
      () => _complaintService.verify(actor, complaintId,
          department: department, note: note),
      'Report verified.');

  Future<void> reject(String reason) => _run(
      () => _complaintService.reject(actor, complaintId, reason),
      'Report rejected. The citizen was notified.');

  Future<void> markDuplicate(String originalId) => _run(
      () => _complaintService.markDuplicate(actor, complaintId, originalId),
      'Merged into $originalId.');

  Future<void> openTender(String title, int budget) => _run(
      () => _jobService.openTender(actor, complaintId,
          title: title, budget: budget),
      'Tender opened. Approved contractors can now bid.');

  Future<void> assignDirectly(String contractorId, int amount) => _run(
      () => _jobService.assignDirectly(actor, complaintId,
          contractorId: contractorId, amount: amount),
      'Contractor assigned.');

  Future<List<DuplicateCandidate>> duplicateCandidates() {
    final c = state.complaint!;
    return _complaintService.findDuplicates(
        title: c.title,
        description: c.description,
        category: c.category,
        location: c.location,
        excludeId: c.id);
  }

  @override
  Future<void> close() async {
    await _cSub?.cancel();
    await _jSub?.cancel();
    return super.close();
  }
}
