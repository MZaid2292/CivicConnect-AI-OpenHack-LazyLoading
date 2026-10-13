import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../utils/geo.dart';

class MapPin {
  const MapPin(
      {required this.point,
      this.color = AppColors.royal,
      this.icon = Icons.location_on,
      this.label});
  final GeoPoint point;
  final Color color;
  final IconData icon;
  final String? label;
}

LatLng toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

class CivicMap extends StatelessWidget {
  const CivicMap({
    super.key,
    required this.config,
    required this.center,
    this.pins = const [],
    this.zoom = 15,
    this.onTap,
    this.interactive = true,
    this.mapController,
  });

  final AppConfig config;
  final GeoPoint center;
  final List<MapPin> pins;
  final double zoom;
  final void Function(GeoPoint point)? onTap;
  final bool interactive;
  final MapController? mapController;

  @override
  Widget build(BuildContext context) {
    final tileUrl = config.tileUrlTemplate;
    final dark = context.civic.isDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: toLatLng(center),
          initialZoom: zoom,
          minZoom: 4,
          maxZoom: 18,
          backgroundColor: context.colors.surfaceContainerHigh,
          interactionOptions: InteractionOptions(
              flags: interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none),
          onTap: onTap == null
              ? null
              : (_, latLng) =>
                  onTap!(GeoPoint(latLng.latitude, latLng.longitude)),
        ),
        children: [
          if (tileUrl != null)
            TileLayer(
              urlTemplate: tileUrl,
              userAgentPackageName: config.tileUserAgentPackageName,
              maxNativeZoom: 19,
              tileBuilder: dark ? darkModeTileBuilder : null,
            )
          else
            _OfflineGrid(color: context.civic.border),
          MarkerLayer(markers: [
            for (final pin in pins)
              Marker(
                point: toLatLng(pin.point),
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: Tooltip(
                  message: pin.label ?? '',
                  child: Icon(pin.icon,
                      color: context.civic.tone(pin.color),
                      size: 40,
                      shadows: const [
                        Shadow(color: Colors.black38, blurRadius: 6)
                      ]),
                ),
              ),
          ]),
          if (tileUrl != null)
            const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors')),
        ],
      ),
    );
  }
}

class _OfflineGrid extends StatelessWidget {
  const _OfflineGrid({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _GridPainter(color),
        child: const SizedBox.expand(),
      );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color;
}
