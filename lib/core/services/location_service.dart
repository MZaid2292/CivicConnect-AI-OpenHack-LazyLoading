import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../utils/geo.dart';

enum LocationFailure { serviceDisabled, denied, deniedForever, timeout, error }

extension LocationFailureText on LocationFailure {
  String get message => switch (this) {
        LocationFailure.serviceDisabled =>
          'Location services are off. Pin the spot on the map instead.',
        LocationFailure.denied =>
          'Location permission denied. You can still pin the spot manually.',
        LocationFailure.deniedForever =>
          'Location is blocked in settings. Pin the spot on the map instead.',
        LocationFailure.timeout =>
          'Could not get a GPS fix in time. Pin the spot on the map instead.',
        LocationFailure.error =>
          'Location is unavailable on this device. Pin the spot manually.',
      };
}

class LocationResult {
  const LocationResult.success(GeoPoint this.point) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : point = null;
  final GeoPoint? point;
  final LocationFailure? failure;
}

abstract class LocationService {
  /// Never throws: failures are returned so the UI can fall back to a pin.
  Future<LocationResult> currentLocation();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationFailure.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failed(LocationFailure.denied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationFailure.deniedForever);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult.success(
          GeoPoint(position.latitude, position.longitude));
    } on TimeoutException {
      return const LocationResult.failed(LocationFailure.timeout);
    } catch (_) {
      return const LocationResult.failed(LocationFailure.error);
    }
  }
}
