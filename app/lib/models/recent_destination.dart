import 'place.dart';

/// One entry in the rider's "recent drops" shortcut list, returned by
/// `GET /api/trips/destinations/recent`. We dedupe server-side by rounded
/// lat/lng, so each entry represents a single "place" the rider has been
/// dropped at one or more times. Tap → set as drop → skip the map picker.
class RecentDestination {
  final String address;
  final double lat;
  final double lng;
  final DateTime lastUsedAt;
  /// How many completed trips ended at this rounded coord bucket. Lets
  /// the UI surface "frequent" places without an extra API call.
  final int tripCount;

  const RecentDestination({
    required this.address,
    required this.lat,
    required this.lng,
    required this.lastUsedAt,
    required this.tripCount,
  });

  /// Convert to a [Place] for handing into [RideFlowState.setDropoff].
  Place toPlace() => Place(address: address, lat: lat, lng: lng);

  factory RecentDestination.fromJson(Map<String, dynamic> json) {
    return RecentDestination(
      address: (json['address'] as String?) ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tripCount: (json['tripCount'] as num?)?.toInt() ?? 1,
    );
  }
}
