import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum MediaSource { camera, gallery }

class PickedMedia {
  const PickedMedia({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

class MediaPickException implements Exception {
  const MediaPickException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class MediaPickerService {
  /// Returns `null` when the user cancels. Throws [MediaPickException] on
  /// permission or platform errors.
  Future<PickedMedia?> pickImage(MediaSource source);
}

/// image_picker implementation. Bytes are read into memory so the same code
/// path works on Android and web (no dart:io File dependency). Images are
/// downscaled to keep memory use reasonable.
class ImagePickerMediaService implements MediaPickerService {
  ImagePickerMediaService([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  static const maxBytes = 8 * 1024 * 1024;

  @override
  Future<PickedMedia?> pickImage(MediaSource source) async {
    // Desktop browsers have no camera capture for file inputs and would open
    // a file dialog instead — say so rather than silently using files.
    if (source == MediaSource.camera &&
        kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw const MediaPickException("Camera capture isn't available in "
          'this browser. Open CivicConnect on a phone to take a photo.');
    }
    try {
      final file = await _picker.pickImage(
        source: source == MediaSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > maxBytes) {
        throw const MediaPickException('That image is too large (max 8 MB).');
      }
      return PickedMedia(bytes: bytes, name: file.name);
    } on MediaPickException {
      rethrow;
    } catch (e) {
      throw MediaPickException(source == MediaSource.camera
          ? 'Camera unavailable or camera permission denied. Allow camera '
              'access in your device settings and try again.'
          : 'Could not open the photo library.');
    }
  }
}
