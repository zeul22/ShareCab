import 'fare_breakdown.dart';
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

  /// Backend MatchGroup id. Null for solo trips (no group). Used as the
  /// route argument when opening the chat screen — see Routes.chat.
  final String? groupId;

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

  /// True when the backend redacted sibling rider details on this trip
  /// (rider-only mode + unlock not yet consumed). The match-result UI
  /// uses this to gate co-rider info behind the unlock sheet.
  /// False in driver-dispatch mode, where matches are always revealed.
  final bool gatedUnlock;

  /// Structured fare breakdown from the backend (`trip.fareBreakdown`).
  /// Null when the proposal predates the new pricing engine (legacy
  /// trip rows) — UI should fall back to the scalar `perRiderFare`
  /// rendered without component details.
  final FareBreakdown? fareBreakdown;

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
    this.groupId,
    this.gatedUnlock = false,
    this.fareBreakdown,
  });

  int get riderCount => coPassengers.length + 1; // +1 for the current user
}
