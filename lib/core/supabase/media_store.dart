import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workflow_exception.dart';
import 'db_errors.dart';

abstract class MediaStore {
  Future<void> upload(String bucket, String path, Uint8List bytes,
      {required String contentType});

  Future<Map<String, String>> signedUrls(String bucket, List<String> paths);
}

class PhotoRules {
  const PhotoRules._();
  static const maxBytes = 5 * 1024 * 1024;

  static (String, String) detect(Uint8List bytes) {
    if (bytes.lengthInBytes > maxBytes) {
      throw const WorkflowException(
          'That photo is larger than 5 MB. Take it again at a lower size.');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ('image/jpeg', 'jpg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ('image/png', 'png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return ('image/webp', 'webp');
    }
    throw const WorkflowException(
        'Only JPEG, PNG or WebP photos can be uploaded.');
  }
}

class SupabaseMediaStore implements MediaStore {
  SupabaseMediaStore(this._client, {this.urlLifetime = 3600});
  final SupabaseClient _client;

  final int urlLifetime;

  @override
  Future<void> upload(String bucket, String path, Uint8List bytes,
          {required String contentType}) =>
      guardDb(() => _client.storage.from(bucket).uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false)));

  @override
  Future<Map<String, String>> signedUrls(
      String bucket, List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final results = await _client.storage
          .from(bucket)
          .createSignedUrlsResult(paths, urlLifetime);
      return {
        for (final r in results.whereType<SignedUrlSuccess>())
          r.path: r.signedUrl,
      };
    } catch (_) {
      return const {};
    }
  }
}
