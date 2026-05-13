import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';
import 'api/ride_api.dart';

/// Default fallback label used when reverse-geocoding fails (no Maps
/// key, no network, etc.). Exposed for tests that want to assert the
/// fallback path explicitly.
const String kCurrentLocationFallbackLabel = 'Current location';

class LocationService extends ChangeNotifier {
  final RideApi? _rideApi;

  LocationService({RideApi? rideApi}) : _rideApi = rideApi;

  Place? _current;
  Place? get current => _current;

  Future<Place?> fetchCurrent() async {
    final allowed = await _ensurePermission();
    if (!allowed) return null;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    // Resolve a real name for the captured pin so the trip persists
    // with a meaningful pickup address — history + analytics surface
    // "Indiranagar, Bengaluru" instead of every row reading "Current
    // location". Reverse-geocoding is best-effort: any failure falls
    // back to the generic label so the rider can still pick up.
    String address = kCurrentLocationFallbackLabel;
    final api = _rideApi;
    if (api != null) {
      try {
        final name = await api.reverseGeocode(
          lat: pos.latitude,
          lng: pos.longitude,
        );
        if (name != null && name.trim().isNotEmpty) {
          address = name.trim();
        }
      } catch (_) {
        // Defense in depth — the HTTP impl already swallows errors
        // and returns null, but a future RideApi impl might throw.
      }
    }
    _current = Place(
      address: address,
      lat: pos.latitude,
      lng: pos.longitude,
    );
    notifyListeners();
    return _current;
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
