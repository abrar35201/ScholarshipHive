import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../core/app_theme.dart';

/// Full-screen "tap the map to place a pin" picker — the same pattern most
/// delivery/ride apps use — so an admin can set an office location precisely
/// without needing to physically stand there or type raw coordinates.
class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  const LocationPickerScreen({super.key, this.initialLatitude, this.initialLongitude});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  ll.LatLng _picked = const ll.LatLng(30.3753, 69.3451); // Pakistan, generic fallback
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _picked = ll.LatLng(widget.initialLatitude!, widget.initialLongitude!);
    } else {
      _goToCurrentLocation();
    }
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
        );
        final point = ll.LatLng(position.latitude, position.longitude);
        if (mounted) {
          setState(() => _picked = point);
          _mapController.move(point, 17);
        }
      }
    } catch (_) {
      // Stay on the fallback view — the admin can still tap anywhere to pick manually.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Office Location'),
        actions: [
          IconButton(
            icon: _locating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
            tooltip: 'Use my current location',
            onPressed: _locating ? null : _goToCurrentLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 16,
              onTap: (tapPosition, point) => setState(() => _picked = point),
            ),
            children: [
              // CARTO's free Voyager tiles — no API key/billing needed (unlike
              // Google Maps), but with the colorful roads/land-use styling and
              // clean English labels that plain OpenStreetMap raster tiles
              // don't have.
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.scholarshiphive.scholarshiphive',
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors © CARTO'),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _picked,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin, size: 44, color: AppColors.primary),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Tap anywhere on the map to move the pin.', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(
                      '${_picked.latitude.toStringAsFixed(6)}, ${_picked.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(_picked),
                        child: const Text('Use This Location'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
