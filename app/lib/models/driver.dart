import 'vehicle.dart';

class Driver {
  final String id;
  final String name;
  final String phoneMasked; // shown as e.g. "98••••3456"
  final double rating;
  final int totalRides;
  final Vehicle vehicle;
  final String photoUrl;

  const Driver({
    required this.id,
    required this.name,
    required this.phoneMasked,
    required this.rating,
    required this.totalRides,
    required this.vehicle,
    this.photoUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneMasked': phoneMasked,
        'rating': rating,
        'totalRides': totalRides,
        'vehicle': vehicle.toJson(),
        'photoUrl': photoUrl,
      };
}
