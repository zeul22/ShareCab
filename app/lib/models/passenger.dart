import 'luggage.dart';
import 'place.dart';

/// A co-passenger as seen by other riders in a match proposal. Only safe
/// fields are exposed (first name, rating, luggage summary) — never phone or
/// last name.
class Passenger {
  final String id;
  final String firstName;
  final double rating;
  final Place pickup;
  final Place dropoff;
  final LuggageProfile luggage;

  const Passenger({
    required this.id,
    required this.firstName,
    required this.rating,
    required this.pickup,
    required this.dropoff,
    required this.luggage,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'rating': rating,
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'luggage': luggage.toJson(),
      };
}
