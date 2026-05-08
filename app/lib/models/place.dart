class Place {
  final String address;
  final double lat;
  final double lng;

  const Place({required this.address, required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {
        'address': address,
        'lat': lat,
        'lng': lng,
      };

  factory Place.fromJson(Map<String, dynamic> json) {
    final coords = (json['location']?['coordinates'] as List?) ?? const [];
    return Place(
      address: json['address'] ?? '',
      lng: coords.isNotEmpty ? (coords[0] as num).toDouble() : 0,
      lat: coords.length > 1 ? (coords[1] as num).toDouble() : 0,
    );
  }
}
