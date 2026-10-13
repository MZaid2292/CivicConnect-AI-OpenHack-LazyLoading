import '../utils/geo.dart';

class AppConfig {
  const AppConfig({
    this.tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.tileUserAgentPackageName = 'com.example.civicconnect_ai',
    this.defaultCenter = const GeoPoint(24.8607, 67.0011),
    this.cityName = 'Demo City',
  });

  const AppConfig.offline()
      : tileUrlTemplate = null,
        tileUserAgentPackageName = 'com.example.civicconnect_ai',
        defaultCenter = const GeoPoint(24.8607, 67.0011),
        cityName = 'Demo City';

  final String? tileUrlTemplate;
  final String tileUserAgentPackageName;

  final GeoPoint defaultCenter;
  final String cityName;
}
