import '../utils/geo.dart';

/// Non-secret runtime configuration for the demo build.
///
/// No backend URLs or keys live here. Supabase configuration will be supplied
/// at build time (e.g. `--dart-define`) during the integration phase.
class AppConfig {
  const AppConfig({
    this.tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.tileUserAgentPackageName = 'com.example.civicconnect_ai',
    this.defaultCenter = const GeoPoint(24.8607, 67.0011),
    this.cityName = 'Demo City',
  });

  /// Config used by tests: no network tile requests.
  const AppConfig.offline()
      : tileUrlTemplate = null,
        tileUserAgentPackageName = 'com.example.civicconnect_ai',
        defaultCenter = const GeoPoint(24.8607, 67.0011),
        cityName = 'Demo City';

  /// OpenStreetMap tile URL. Respect the OSM tile usage policy: identify the
  /// app via user agent, show attribution, and never bulk-download tiles.
  /// Set to `null` to render an offline placeholder grid instead of tiles.
  final String? tileUrlTemplate;
  final String tileUserAgentPackageName;

  /// Map centre used when GPS is unavailable and for seeded demo reports.
  final GeoPoint defaultCenter;
  final String cityName;
}
