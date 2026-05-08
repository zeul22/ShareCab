import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';

class LocationService extends ChangeNotifier {
  Place? _current;
  Place? get current => _current;

  Future<Place?> fetchCurrent() async {
    final allowed = await _ensurePermission();
    if (!allowed) return null;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _current = Place(address: 'Current location', lat: pos.latitude, lng: pos.longitude);
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
