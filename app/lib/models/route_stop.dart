import 'place.dart';

enum StopKind { pickup, dropoff }

/// One stop on a shared ride's route. The matching engine sequences these
/// to produce the pickup→pickup→...→dropoff→dropoff→... ordering.
class RouteStop {
  final StopKind kind;
  final Place place;
  final String passengerId;
  final String passengerFirstName;

  /// Sequence number on the route (0-indexed). Set by the matching engine.
  final int order;

  /// Estimated minutes from the start of the ride to this stop.
  final int etaFromStartMin;

  const RouteStop({
    required this.kind,
    required this.place,
    required this.passengerId,
    required this.passengerFirstName,
    required this.order,
    required this.etaFromStartMin,
  });
}
