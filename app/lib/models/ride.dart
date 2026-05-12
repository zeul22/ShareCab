import 'driver.dart';
import 'match_proposal.dart';
import 'passenger.dart';
import 'place.dart';

enum RideStatus {
  confirmed, // accepted, awaiting driver pickup
  arriving, // driver is en route to pickup
  inProgress, // ride underway
  completed,
  cancelled,
}

/// A confirmed ride — the post-acceptance object that the live ride / OTP /
/// payment / completed screens consume.
class Ride {
  final String id;
  final MatchProposal proposal;
  final Driver driver;

  /// 4-digit OTP shown to the rider after confirmation. The driver enters it
  /// at pickup so both sides verify each other.
  final String otp;

  final RideStatus status;
  final DateTime confirmedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// All riders (current user + co-passengers). The current user is implicit
  /// in [proposal] but we keep this list for convenience on the UI.
  final List<Passenger> riders;

  /// Per-rider amount due in INR. Mirrors [proposal.perRiderFare] at
  /// confirmation time.
  final double perRiderFare;

  /// Actual GPS where the driver tapped "Picked up" — backend persists
  /// this on the Trip and the rider's map snaps the source pin here once
  /// the trip transitions to in_progress. Null until the pickup happens
  /// (or always, on legacy trips that predate actual-capture).
  final Place? actualPickup;

  /// Actual GPS where the driver tapped "Dropped". Used by the
  /// completed-ride screen + audit.
  final Place? actualDropoff;

  const Ride({
    required this.id,
    required this.proposal,
    required this.driver,
    required this.otp,
    required this.status,
    required this.confirmedAt,
    required this.riders,
    required this.perRiderFare,
    this.startedAt,
    this.completedAt,
    this.actualPickup,
    this.actualDropoff,
  });

  Ride copyWith({
    RideStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    Place? actualPickup,
    Place? actualDropoff,
  }) =>
      Ride(
        id: id,
        proposal: proposal,
        driver: driver,
        otp: otp,
        status: status ?? this.status,
        confirmedAt: confirmedAt,
        riders: riders,
        perRiderFare: perRiderFare,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        actualPickup: actualPickup ?? this.actualPickup,
        actualDropoff: actualDropoff ?? this.actualDropoff,
      );
}
