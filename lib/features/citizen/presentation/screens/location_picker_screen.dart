import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/civic_map.dart';
import '../../../../core/widgets/civic_widgets.dart';

/// Full-screen map: tap to drop a pin, then confirm. Works without GPS.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.config, this.initial});
  final AppConfig config;
  final GeoPoint? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GeoPoint? _pin;

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CivicAppBar(
            title: 'Pin the location', subtitle: 'Tap the map to drop a pin'),
        body: Stack(children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: CivicMap(
                config: widget.config,
                center: widget.initial ?? widget.config.defaultCenter,
                zoom: 15,
                onTap: (p) => setState(() => _pin = p),
                pins: [
                  if (_pin != null)
                    MapPin(point: _pin!, color: AppColors.red, label: 'Issue'),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _pin == null
                      ? 'Tap the map where the issue is. An approximate spot is fine.'
                      : 'Pinned at ${_pin!.shortLabel}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FilledButton.icon(
              onPressed:
                  _pin == null ? null : () => Navigator.pop(context, _pin),
              icon: const Icon(Icons.check),
              label: const Text('Use this location'),
            ),
          ),
        ),
      );
}
