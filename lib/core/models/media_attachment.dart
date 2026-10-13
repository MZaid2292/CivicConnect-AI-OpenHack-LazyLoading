import 'dart:typed_data';

import 'package:equatable/equatable.dart';

enum MediaStorage {
  seedIllustration,

  localMemory,

  remoteUpload,
}

enum EvidenceStage { report, before, progress, after }

class MediaAttachment extends Equatable {
  const MediaAttachment({
    required this.id,
    required this.storage,
    required this.caption,
    this.bytes,
    this.remoteUrl,
    this.stage = EvidenceStage.report,
  });

  final String id;
  final MediaStorage storage;
  final String caption;
  final Uint8List? bytes;
  final String? remoteUrl;
  final EvidenceStage stage;

  bool get isLocalOnly => storage == MediaStorage.localMemory;

  String get storageLabel => switch (storage) {
        MediaStorage.seedIllustration => 'Sample illustration',
        MediaStorage.localMemory => 'Local only · not uploaded',
        MediaStorage.remoteUpload => 'Uploaded',
      };

  @override
  List<Object?> get props => [id, storage, caption, stage, remoteUrl];
}
