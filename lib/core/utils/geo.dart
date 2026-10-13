import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Backend-agnostic coordinate used by the domain layer.
class GeoPoint extends Equatable {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  /// Offsets this point by metres north/east (good enough for city scale).
  GeoPoint offsetMeters({double north = 0, double east = 0}) {
    const metresPerDegree = 111320.0;
    final dLat = north / metresPerDegree;
    final dLng = east / (metresPerDegree * math.cos(latitude * math.pi / 180));
    return GeoPoint(latitude + dLat, longitude + dLng);
  }

  String get shortLabel =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  @override
  List<Object?> get props => [latitude, longitude];
}

const _earthRadiusMeters = 6371000.0;

/// Great-circle distance between two points using the Haversine formula.
double haversineMeters(GeoPoint a, GeoPoint b) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
