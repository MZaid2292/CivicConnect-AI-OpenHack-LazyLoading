import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/models/media_attachment.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/media_picker_service.dart';
import '../../../../core/utils/geo.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/services/category_classifier.dart';
import '../../../complaints/domain/services/complaint_service.dart';
import '../../../complaints/domain/services/duplicate_detector.dart';
import '../../../complaints/domain/services/priority_engine.dart';

enum CreateOutcome { none, submitted, draftSaved, supportedExisting }

class CreateComplaintState extends Equatable {
  const CreateComplaintState({
    this.draftId,
    this.loadingDraft = false,
    this.title = '',
    this.description = '',
    this.address = '',
    this.category,
    this.categoryManuallySet = false,
    this.classification = const ClassificationResult.empty(),
    this.priority,
    this.duplicates = const [],
    this.duplicatesAcknowledged = false,
    this.photos = const [],
    this.location,
    this.locationSource = LocationSource.none,
    this.locating = false,
    this.locationMessage,
    this.busy = false,
    this.error,
    this.showValidation = false,
    this.outcome = CreateOutcome.none,
    this.outcomeId,
  });

  final String? draftId;
  final bool loadingDraft;
  final String title;
  final String description;
  final String address;
  final ComplaintCategory? category;
  final bool categoryManuallySet;
  final ClassificationResult classification;
  final PriorityAssessment? priority;
  final List<DuplicateCandidate> duplicates;
  final bool duplicatesAcknowledged;
  final List<MediaAttachment> photos;
  final GeoPoint? location;
  final LocationSource locationSource;
  final bool locating;
  final String? locationMessage;
  final bool busy;
  final String? error;
  final bool showValidation;
  final CreateOutcome outcome;
  final String? outcomeId;

  String? get titleError =>
      showValidation ? ComplaintValidator.title(title) : null;
  String? get descriptionError =>
      showValidation ? ComplaintValidator.description(description) : null;
  String? get addressError =>
      showValidation ? ComplaintValidator.address(address) : null;
  String? get categoryError =>
      showValidation && category == null ? 'Choose a category.' : null;

  bool get isValid =>
      ComplaintValidator.title(title) == null &&
      ComplaintValidator.description(description) == null &&
      ComplaintValidator.address(address) == null &&
      category != null;

  bool get needsDuplicateDecision =>
      duplicates.isNotEmpty && !duplicatesAcknowledged;

  CreateComplaintState copyWith({
    String? draftId,
    bool? loadingDraft,
    String? title,
    String? description,
    String? address,
    ComplaintCategory? category,
    bool? categoryManuallySet,
    ClassificationResult? classification,
    PriorityAssessment? priority,
    List<DuplicateCandidate>? duplicates,
    bool? duplicatesAcknowledged,
    List<MediaAttachment>? photos,
    GeoPoint? location,
    LocationSource? locationSource,
    bool? locating,
    String? locationMessage,
    bool clearLocationMessage = false,
    bool? busy,
    String? error,
    bool? showValidation,
    CreateOutcome? outcome,
    String? outcomeId,
  }) =>
      CreateComplaintState(
        draftId: draftId ?? this.draftId,
        loadingDraft: loadingDraft ?? this.loadingDraft,
        title: title ?? this.title,
        description: description ?? this.description,
        address: address ?? this.address,
        category: category ?? this.category,
        categoryManuallySet: categoryManuallySet ?? this.categoryManuallySet,
        classification: classification ?? this.classification,
        priority: priority ?? this.priority,
        duplicates: duplicates ?? this.duplicates,
        duplicatesAcknowledged:
            duplicatesAcknowledged ?? this.duplicatesAcknowledged,
        photos: photos ?? this.photos,
        location: location ?? this.location,
        locationSource: locationSource ?? this.locationSource,
        locating: locating ?? this.locating,
        locationMessage: clearLocationMessage
            ? null
            : (locationMessage ?? this.locationMessage),
        busy: busy ?? this.busy,
        error: error,
        showValidation: showValidation ?? this.showValidation,
        outcome: outcome ?? this.outcome,
        outcomeId: outcomeId ?? this.outcomeId,
      );

  @override
  List<Object?> get props => [
        draftId,
        loadingDraft,
        title,
        description,
        address,
        category,
        categoryManuallySet,
        classification,
        priority,
        duplicates,
        duplicatesAcknowledged,
        photos,
        location,
        locationSource,
        locating,
        locationMessage,
        busy,
        error,
        showValidation,
        outcome,
        outcomeId,
      ];
}

/// View model for the report form. All intelligence (classification,
/// duplicate detection, priority) comes from domain services.
class CreateComplaintCubit extends Cubit<CreateComplaintState> {
  CreateComplaintCubit({
    required ComplaintService service,
    required LocationService location,
    required MediaPickerService media,
    required Actor actor,
    required GeoPoint wardCentre,
    String? draftId,
  })  : _service = service,
        _location = location,
        _media = media,
        _actor = actor,
        _wardCentre = wardCentre,
        super(CreateComplaintState(
            draftId: draftId, loadingDraft: draftId != null)) {
    if (draftId != null) _loadDraft(draftId);
  }

  final ComplaintService _service;
  final LocationService _location;
  final MediaPickerService _media;
  final Actor _actor;
  final GeoPoint _wardCentre;
  int _duplicateRequest = 0;
  static const _uuid = Uuid();

  Future<void> _loadDraft(String id) async {
    final draft = await _service.findById(id);
    if (draft == null ||
        draft.status != ComplaintStatus.draft ||
        draft.reporterId != _actor.id) {
      emit(state.copyWith(
          loadingDraft: false, error: 'That draft is no longer available.'));
      return;
    }
    emit(state.copyWith(
      loadingDraft: false,
      title: draft.title,
      description: draft.description,
      address: draft.address,
      category: draft.category,
      categoryManuallySet: true,
      photos: draft.photos,
      location: draft.location,
      locationSource: draft.locationSource,
    ));
    _analyse();
  }

  void updateText({String? title, String? description, String? address}) {
    emit(state.copyWith(
        title: title, description: description, address: address));
    if (title != null || description != null) _analyse();
  }

  void selectCategory(ComplaintCategory category) {
    emit(state.copyWith(category: category, categoryManuallySet: true));
    _analyse();
  }

  void acceptSuggestion() {
    final top = state.classification.top;
    if (top == null) return;
    emit(state.copyWith(category: top.category, categoryManuallySet: false));
    _analyse();
  }

  void _analyse() {
    final classification = _service.classify(state.title, state.description);
    final category = state.categoryManuallySet
        ? state.category
        : (classification.top?.category ?? state.category);
    emit(state.copyWith(
      classification: classification,
      category: category,
      priority: category == null
          ? null
          : _service.previewPriority(
              category: category,
              title: state.title,
              description: state.description),
    ));
    _refreshDuplicates();
  }

  Future<void> _refreshDuplicates() async {
    final category = state.category;
    if (category == null || state.title.trim().length < 4) {
      emit(state.copyWith(duplicates: const []));
      return;
    }
    final request = ++_duplicateRequest;
    // A ward-centre fallback is not a real position — use text-only matching.
    final precise = state.locationSource == LocationSource.gps ||
        state.locationSource == LocationSource.manualPin;
    final result = await _service.findDuplicates(
      title: state.title,
      description: state.description,
      category: category,
      location: precise ? state.location : null,
      excludeId: state.draftId,
    );
    if (request != _duplicateRequest || isClosed) return;
    final changed = result.map((d) => d.complaint.id).join() !=
        state.duplicates.map((d) => d.complaint.id).join();
    emit(state.copyWith(
        duplicates: result,
        duplicatesAcknowledged:
            changed ? false : state.duplicatesAcknowledged));
  }

  Future<void> detectLocation() async {
    emit(state.copyWith(locating: true, clearLocationMessage: true));
    final result = await _location.currentLocation();
    if (isClosed) return;
    if (result.point != null) {
      emit(state.copyWith(
          locating: false,
          location: result.point,
          locationSource: LocationSource.gps,
          locationMessage: 'Approximate GPS position captured.'));
    } else {
      emit(state.copyWith(
          locating: false, locationMessage: result.failure!.message));
    }
    _refreshDuplicates();
  }

  void setPinnedLocation(GeoPoint point) {
    emit(state.copyWith(
        location: point,
        locationSource: LocationSource.manualPin,
        locationMessage: 'Location pinned on the map.'));
    _refreshDuplicates();
  }

  void useWardCentre() {
    emit(state.copyWith(
        location: _wardCentre,
        locationSource: LocationSource.defaultArea,
        locationMessage:
            'Using the ward centre. Add a clear landmark in the address.'));
    _refreshDuplicates();
  }

  Future<void> addPhoto(MediaSource source) async {
    if (state.photos.length >= 4) {
      emit(state.copyWith(error: 'You can attach up to 4 photos.'));
      return;
    }
    try {
      final picked = await _media.pickImage(source);
      if (picked == null || isClosed) return; // user cancelled
      emit(state.copyWith(photos: [
        ...state.photos,
        MediaAttachment(
          id: _uuid.v4(),
          storage: MediaStorage.localMemory,
          caption: picked.name,
          bytes: picked.bytes,
        ),
      ]));
    } on MediaPickException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  void removePhoto(String id) => emit(
      state.copyWith(photos: state.photos.where((p) => p.id != id).toList()));

  void acknowledgeDuplicates() =>
      emit(state.copyWith(duplicatesAcknowledged: true));

  Future<void> supportExisting(String complaintId) async {
    emit(state.copyWith(busy: true));
    try {
      final existing = await _service.findById(complaintId);
      if (existing != null &&
          !existing.supporterIds.contains(_actor.id) &&
          existing.reporterId != _actor.id) {
        await _service.toggleSupport(_actor, complaintId);
      }
      emit(state.copyWith(
          busy: false,
          outcome: CreateOutcome.supportedExisting,
          outcomeId: complaintId));
    } catch (e) {
      emit(state.copyWith(busy: false, error: e.toString()));
    }
  }

  ComplaintInput _input() => ComplaintInput(
        title: state.title,
        description: state.description,
        category: state.category ?? ComplaintCategory.other,
        address: state.address,
        location: state.location,
        locationSource: state.locationSource,
        photos: state.photos,
      );

  /// Returns false when validation or the duplicate decision blocks submit.
  Future<bool> submit() async {
    emit(state.copyWith(showValidation: true));
    if (!state.isValid) {
      emit(state.copyWith(error: 'Please fix the highlighted fields.'));
      return false;
    }
    if (state.needsDuplicateDecision) return false;
    emit(state.copyWith(busy: true));
    try {
      final created =
          await _service.submit(_actor, _input(), draftId: state.draftId);
      emit(state.copyWith(
          busy: false,
          outcome: CreateOutcome.submitted,
          outcomeId: created.id));
      return true;
    } catch (e) {
      emit(state.copyWith(busy: false, error: e.toString()));
      return false;
    }
  }

  Future<void> saveDraft() async {
    if (state.title.trim().isEmpty && state.description.trim().isEmpty) {
      emit(state.copyWith(error: 'Add a title or description first.'));
      return;
    }
    emit(state.copyWith(busy: true));
    try {
      final draft =
          await _service.saveDraft(_actor, _input(), draftId: state.draftId);
      emit(state.copyWith(
          busy: false,
          draftId: draft.id,
          outcome: CreateOutcome.draftSaved,
          outcomeId: draft.id));
    } catch (e) {
      emit(state.copyWith(busy: false, error: e.toString()));
    }
  }
}
