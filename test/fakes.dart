import 'dart:typed_data';

import 'package:civicconnect_ai/core/services/location_service.dart';
import 'package:civicconnect_ai/core/services/media_picker_service.dart';
import 'package:civicconnect_ai/core/utils/geo.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({this.result});
  final LocationResult? result;

  @override
  Future<LocationResult> currentLocation() async =>
      result ?? const LocationResult.failed(LocationFailure.denied);
}

class FakeMediaPicker implements MediaPickerService {
  FakeMediaPicker({this.cancel = false});
  final bool cancel;

  /// Source of the most recent request, for asserting camera-only flows.
  MediaSource? lastSource;

  @override
  Future<PickedMedia?> pickImage(MediaSource source) async {
    lastSource = source;
    return cancel
        ? null
        : PickedMedia(bytes: Uint8List.fromList(_png), name: 'test.png');
  }
}

const sampleGps = GeoPoint(24.8607, 67.0011);

/// 1×1 transparent PNG.
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
