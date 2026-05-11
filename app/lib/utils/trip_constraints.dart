import '../models/place.dart';
import '../services/matching/geo.dart';

/// Trip-distance sanity rails. These mirror the backend's
/// `env.trip.{minDistanceKm,maxDistanceKm}` exactly — keep both sides
/// in sync. The client-side check is a UX nicety (instant feedback,
/// disabled Continue button); the backend zod refine is the authority.
class TripConstraints {
  TripConstraints._();

  /// Pickup→drop straight-line distance below this is rejected as a
  /// misclick / same-address pair.
  static const double minTripKm = 0.3;

  /// Above this is intercity (Mumbai↔Pune is ~150 km, Bangalore↔Delhi
  /// is ~1700 km) — ShareCab isn't built for those.
  static const double maxTripKm = 100.0;

  /// Validate the pickup ↔ drop pair. Returns null when both fields
  /// are unset (let the caller show "set destination" hints) OR when
  /// the pair is valid; returns a short, user-facing error otherwise.
  static String? validate(Place? pickup, Place? drop) {
    if (pickup == null || drop == null) return null;
    final km = distanceKm(pickup, drop);
    if (km < minTripKm) {
      return 'Pickup and drop are too close (${km.toStringAsFixed(2)} km). '
          'Pick locations at least ${(minTripKm * 1000).toStringAsFixed(0)} m apart.';
    }
    if (km > maxTripKm) {
      return 'Trip is too far (${km.toStringAsFixed(0)} km). '
          'ShareCab is for short city rides up to ${maxTripKm.toStringAsFixed(0)} km — '
          'try a taxi service for intercity trips.';
    }
    return null;
  }
}
