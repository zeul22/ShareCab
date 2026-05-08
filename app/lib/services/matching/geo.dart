import 'dart:math';

import '../../models/place.dart';

/// Haversine distance between two places in km. Mirrors the backend's
/// `utils/geo.js` so client-side previews match server-side decisions.
double distanceKm(Place a, Place b) {
  const earthKm = 6371.0;
  double rad(double d) => d * pi / 180.0;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final lat1 = rad(a.lat);
  final lat2 = rad(b.lat);
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * earthKm * asin(sqrt(h));
}
