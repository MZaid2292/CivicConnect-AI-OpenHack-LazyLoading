import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/geo.dart';

/// Turns coordinates into a readable street / area. Never throws: null means
/// "no useful address" and the form falls back to the coordinates.
abstract class ReverseGeocoder {
  Future<String?> addressFor(GeoPoint point);
}

/// Free OpenStreetMap Nominatim lookup (no API key, no paid service).
///
/// Follows the Nominatim usage policy: one request per explicit user action
/// ("Use my location"), at most one request per second, an identifying
/// User-Agent (browsers send their own Referer instead), results cached per
/// ~11 m cell, and attribution via the OSM map already shown on the form.
class NominatimReverseGeocoder implements ReverseGeocoder {
  NominatimReverseGeocoder({
    http.Client? client,
    this.userAgent = 'CivicConnectAI/1.0 (com.example.civicconnect_ai)',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;
  final Duration timeout;
  final _cache = <String, String?>{};
  DateTime? _lastRequest;

  @override
  Future<String?> addressFor(GeoPoint point) async {
    final key = '${point.latitude.toStringAsFixed(4)},'
        '${point.longitude.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) return _cache[key];
    final last = _lastRequest;
    if (last != null) {
      final wait = const Duration(seconds: 1) - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequest = DateTime.now();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await _client.get(uri, headers: {
        if (!kIsWeb) 'User-Agent': userAgent,
        'Accept-Language': 'en',
      }).timeout(timeout);
      if (response.statusCode != 200) return null;
      final address = formatAddress(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
      return _cache[key] = address;
    } catch (_) {
      return null; // offline, timeout, rate limit or bad response
    }
  }

  /// Short "road, area, city" line from a Nominatim result.
  @visibleForTesting
  static String? formatAddress(Map<String, dynamic> json) {
    final a = json['address'];
    if (a is Map) {
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final parts = <String>[
        for (final p in [
          [
            pick(['house_number']),
            pick(['road', 'pedestrian', 'footway'])
          ].whereType<String>().join(' '),
          pick(['neighbourhood', 'suburb', 'quarter', 'residential']) ?? '',
          pick(['city', 'town', 'village', 'municipality', 'county']) ?? '',
        ])
          if (p.trim().isNotEmpty) p.trim(),
      ];
      final unique = parts.toSet().toList();
      if (unique.isNotEmpty) return unique.join(', ');
    }
    final display = json['display_name'];
    if (display is String && display.trim().isNotEmpty) {
      return display.split(',').take(3).map((s) => s.trim()).join(', ');
    }
    return null;
  }
}
