import 'place.dart';

/// Pending dispatch offer returned by `GET /api/drivers/me/offer`.
///
/// The driver app's home screen polls every 3 seconds while online +
/// unassigned. When an offer comes in, the screen pops the
/// [IncomingOfferSheet] which surfaces this data and counts down
/// `expiresAt`. The backend will auto-reject after the same window so
/// the UI's timer is matching the wire-level contract.
class TripOffer {
  final String tripId;
  final String riderName;
  final double riderRating;
  final String? riderPhone;
  final Place pickup;
  final Place dropoff;

  /// Fare estimate in PAISE (matches Razorpay + the Fare schema).
  /// UI divides by 100 for display.
  final int fareEstimatePaise;

  /// When the backend will auto-reject this offer. Drives the countdown
  /// ring; converted from the server's ISO timestamp at parse time so
  /// clock skew is bounded by network latency, not duration.
  final DateTime expiresAt;

  /// Number of riders in the dispatched group. 1 for solo trips; 2-3 for
  /// shared. Affects the sheet's headline ("1 rider" vs "2 riders sharing").
  final int groupSize;

  const TripOffer({
    required this.tripId,
    required this.riderName,
    required this.riderRating,
    required this.pickup,
    required this.dropoff,
    required this.fareEstimatePaise,
    required this.expiresAt,
    required this.groupSize,
    this.riderPhone,
  });

  double get fareEstimateRupees => fareEstimatePaise / 100;

  /// Seconds left until auto-reject. Floor — the UI rounds down so
  /// "1 second" doesn't render after the wire actually expired.
  int secondsRemaining() {
    final ms = expiresAt.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return ms ~/ 1000;
  }

  /// Parse from the backend's populated Trip + matchGroup response shape:
  ///   { offer: { _id, rider: {name, rating, phone}, pickup, dropoff,
  ///              fareEstimate, offerExpiresAt, matchGroup?: { trips: [...] } } }
  factory TripOffer.fromTripJson(Map<String, dynamic> trip) {
    final rider = (trip['rider'] as Map?)?.cast<String, dynamic>() ?? const {};
    final group = (trip['matchGroup'] as Map?)?.cast<String, dynamic>();
    final groupSize = group != null && group['trips'] is List
        ? (group['trips'] as List).length
        : 1;
    return TripOffer(
      tripId: (trip['_id'] as String?) ?? '',
      riderName: (rider['name'] as String?) ?? 'Rider',
      riderRating: (rider['rating'] as num?)?.toDouble() ?? 5.0,
      riderPhone: rider['phone'] as String?,
      pickup: Place.fromJson(
          (trip['pickup'] as Map<String, dynamic>?) ?? const {}),
      dropoff: Place.fromJson(
          (trip['dropoff'] as Map<String, dynamic>?) ?? const {}),
      fareEstimatePaise: (trip['fareEstimate'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(trip['offerExpiresAt']?.toString() ?? '') ??
          DateTime.now().add(const Duration(seconds: 15)),
      groupSize: groupSize,
    );
  }
}
