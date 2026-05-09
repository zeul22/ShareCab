import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/place.dart';
import '../services/api/places_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_config.dart';
import '../widgets/place_search_field.dart';

/// Full-screen picker that returns a [Place] to the caller via Navigator.pop.
///
/// Two ways to choose a point:
///   1. Type into the Places autocomplete search bar (uses [PlacesService]).
///   2. Drag the map; the centered pin marks the selected point.
class MapPickerScreen extends StatefulWidget {
  final String title;
  final Place? initial;

  const MapPickerScreen({super.key, required this.title, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _map;
  final _searchCtrl = TextEditingController();
  late final PlacesService _places;

  // Default to a sensible city center if no initial point was supplied.
  // Bengaluru (HSR Layout area) — primary launch city.
  static const LatLng _defaultCenter = LatLng(12.9148106, 77.6764023);

  late LatLng _center;
  String _address = '';

  // Reverse-geocode debounce — fires 600ms after the camera stops moving,
  // so we don't spam the Geocoding API on every pixel drag.
  Timer? _geocodeDebounce;
  bool _resolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _places = PlacesService(apiKey: ApiConfig.googleMapsKey);
    if (widget.initial != null) {
      _center = LatLng(widget.initial!.lat, widget.initial!.lng);
      _address = widget.initial!.address;
      _searchCtrl.text = widget.initial!.address;
    } else {
      _center = _defaultCenter;
      // Resolve the default-center address once so the rider sees something
      // meaningful before they touch the map.
      _scheduleReverseGeocode();
    }
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _searchCtrl.dispose();
    _map?.dispose();
    _places.dispose();
    super.dispose();
  }

  void _onPlaceSelected(PlaceDetails details) {
    _geocodeDebounce?.cancel();
    setState(() {
      _center = LatLng(details.lat, details.lng);
      _address = details.formattedAddress;
      _resolvingAddress = false;
    });
    _map?.animateCamera(CameraUpdate.newLatLngZoom(_center, 16));
  }

  /// Called from `onCameraIdle`. Debounces so a quick fling-and-settle pair
  /// produces one geocode call, not several.
  void _scheduleReverseGeocode() {
    _geocodeDebounce?.cancel();
    setState(() => _resolvingAddress = true);
    _geocodeDebounce = Timer(const Duration(milliseconds: 600), _resolveAddress);
  }

  Future<void> _resolveAddress() async {
    final captured = _center;
    try {
      final addr = await _places.reverseGeocode(
        captured.latitude,
        captured.longitude,
      );
      if (!mounted) return;
      // If the camera moved on while we were waiting, this result is stale —
      // a fresher call will overwrite. Comparing LatLng values is safe; equal
      // pairs mean nothing budged.
      if (captured.latitude != _center.latitude ||
          captured.longitude != _center.longitude) {
        return;
      }
      setState(() {
        _address = addr ?? '';
        _searchCtrl.text = addr ?? '';
        _resolvingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvingAddress = false);
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      Place(
        // Last-resort fallback only — by the time the user taps Confirm, the
        // camera has been idle long enough for reverse geocoding to have
        // resolved an address (assuming the API key is configured + has the
        // Geocoding API enabled).
        address: _address.isEmpty
            ? '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}'
            : _address,
        lat: _center.latitude,
        lng: _center.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 15),
            onMapCreated: (c) => _map = c,
            onCameraMove: (pos) => _center = pos.target,
            // Once the camera settles, kick off a debounced reverse-geocode
            // so the address chip below the pin updates with a real address
            // wherever the rider drops it.
            onCameraIdle: _scheduleReverseGeocode,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Centered pin overlay.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: Icon(Icons.location_pin, size: 48, color: AppTheme.brand),
              ),
            ),
          ),

          // Search bar + suggestions list.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: PlaceSearchField(
                controller: _searchCtrl,
                service: _places,
                onPlaceSelected: _onPlaceSelected,
              ),
            ),
          ),

          // Resolved-address chip + Confirm button, stacked at the bottom.
          // The chip shows the live reverse-geocoded address for whatever
          // point is currently under the pin — visual confirmation that the
          // rider is about to commit the right location.
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 18, color: AppTheme.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _resolvingAddress
                              ? 'Resolving address…'
                              : (_address.isEmpty
                                  ? 'Drag the map to pick a location'
                                  : _address),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                      if (_resolvingAddress)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _confirm,
                    child: Text('Confirm ${widget.title.toLowerCase()}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
