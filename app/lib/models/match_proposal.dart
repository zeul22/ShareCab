import 'passenger.dart';
import 'route_stop.dart';
import 'vehicle.dart';

/// A candidate match the user can accept or reject.
///
/// The matching engine produces these from a [RideSearch]; the user's own
/// passenger row is included in [coPassengers] only conceptually — the UI
/// shows "you" plus the others.
class MatchProposal {
  final String id;
  final List<Passenger> coPassengers;
  final List<RouteStop> stops;
  final VehicleType vehicleType;

  /// Group total fare (all riders combined), in INR.
  final double groupFare;

  /// Per-rider share (after the share discount), in INR.
  final double perRiderFare;

  /// Total ride distance across all stops, in km.
  final double distanceKm;

  /// Total ride duration end-to-end, in minutes.
  final int durationMin;

  /// Luggage seats consumed by all riders combined (for transparency).
  final int luggageSeatsUsed;

  /// Luggage seats still available — non-negative is required for a valid match.
  final int luggageSeatsFree;

  const MatchProposal({
    required this.id,
    required this.coPassengers,
    required this.stops,
    required this.vehicleType,
    required this.groupFare,
    required this.perRiderFare,
    required this.distanceKm,
    required this.durationMin,
    required this.luggageSeatsUsed,
    required this.luggageSeatsFree,
  });

  int get riderCount => coPassengers.length + 1; // +1 for the current user
}
