/// Driver's current GPS + ETA payload from `GET /trips/:id/driver-location`.
/// Polled by [TripTrackingService] every 5s while the rider is on the
/// live-ride screen and the trip is in `arriving` or `in_progress`.
class DriverLiveLocation {
  final double lat;
  final double lng;
  final DateTime updatedAt;

  const DriverLiveLocation({
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  factory DriverLiveLocation.fromJson(Map<String, dynamic> json) {
    return DriverLiveLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '')
          ?? DateTime.now(),
    );
  }
}

/// ETA to the next pending stop. `toStop` is the leg we're computing for
/// — 'pickup' before the rider boards, 'dropoff' once they're in the cab.
class TripEta {
  final String toStop; // 'pickup' | 'dropoff'
  final int seconds;
  final int distanceMeters;

  /// Where the time/distance came from: 'directions' (Google routed) or
  /// 'haversine' (straight-line fallback when the key is unavailable).
  /// Surfaced so the rider chip can hint "approx" when haversine.
  final String source;

  const TripEta({
    required this.toStop,
    required this.seconds,
    required this.distanceMeters,
    required this.source,
  });

  /// Minutes, ceil — "1 min" sounds better than "0 min" for sub-30s ETAs.
  int get minutes => seconds <= 0 ? 0 : ((seconds + 59) ~/ 60);

  bool get isApproximate => source == 'haversine';
  bool get isToPickup => toStop == 'pickup';
  bool get isToDropoff => toStop == 'dropoff';

  factory TripEta.fromJson(Map<String, dynamic> json) {
    return TripEta(
      toStop: (json['toStop'] as String?) ?? 'pickup',
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      source: (json['source'] as String?) ?? 'haversine',
    );
  }
}

/// Combined response shape from `GET /trips/:id/driver-location`. ETA can
/// be null when the trip status doesn't have an active leg (e.g. matched
/// but no driver assigned yet, or just-completed).
class DriverLocationResponse {
  final DriverLiveLocation driver;
  final TripEta? eta;

  const DriverLocationResponse({required this.driver, this.eta});

  factory DriverLocationResponse.fromJson(Map<String, dynamic> json) {
    final eta = json['eta'];
    return DriverLocationResponse(
      driver: DriverLiveLocation.fromJson(
          (json['driver'] as Map).cast<String, dynamic>()),
      eta: eta is Map<String, dynamic> ? TripEta.fromJson(eta) : null,
    );
  }
}
