import 'dart:math';

import '../../models/match_proposal.dart';
import '../../models/passenger.dart';
import '../../models/place.dart';
import '../../models/ride_search.dart';
import '../../models/route_stop.dart';
import '../../models/vehicle.dart';
import 'geo.dart';
import 'luggage_rules.dart';
import 'vehicle_rules.dart';

/// Pure matching logic. Given the searching user's request and a pool of
/// other concurrent searchers, return zero or more compatible groups they
/// could share a cab with.
///
/// Constraints applied (in order):
///   1. Pickup compatibility: every rider's pickup is within ~2 km of
///      the group centroid (small detour).
///   2. Destination compatibility: every rider's drop is within 2-4 km
///      of the group centroid drop.
///   3. Active-window: only riders whose search started within the
///      last `activeWindow` are considered "concurrent".
///   4. Airport mode: if the searching user is in airport mode, only
///      pair with other airport-mode riders whose landing time is within
///      `airportPairWindow` of theirs.
///   5. Vehicle capacity: total riders ≤ vehicle.maxSharedRiders.
///   6. Luggage capacity: combined luggage seats ≤ vehicle.luggageCapacity.
///
/// "Random compatible" mode skips the destination-radius check (it still
/// requires pickups + route + capacity to be sane), as per the brief:
/// "Random does not mean fully unrestricted."
class MatchingEngine {
  static const double pickupRadiusKm = 2.0;
  static const double destNearbyRadiusKm = 4.0;
  static const Duration activeWindow = Duration(minutes: 10);
  static const Duration airportPairWindow = Duration(minutes: 30);
  static const int maxGroupsToReturn = 3;

  // Fare model — mirrors backend defaults (see backend/.env.example).
  static const double fareBase = 30;
  static const double farePerKm = 12;
  static const double farePerMin = 1;
  static const double shareDiscount = 0.30;
  static const double averageSpeedKmph = 25;

  /// Find candidate groups for [search] given the [pool] of other concurrent
  /// users currently searching. Pass [now] to make this deterministic in tests.
  ///
  /// Returns proposals best-first. Empty list = no compatible match yet.
  static List<MatchProposal> findGroups({
    required RideSearch search,
    required List<Passenger> pool,
    required DateTime now,
  }) {
    if (!search.isReadyToSearch) return const [];

    final selfLuggageSeats = LuggageRules.seatsConsumed(search.luggage);

    // Filter the pool by hard constraints (pickup, destination, airport, time).
    // For mock purposes we model "active window" implicitly: callers feed us
    // only currently-searching passengers.
    final candidates = pool.where((p) {
      // Pickup proximity — both modes require this.
      if (distanceKm(search.pickup!, p.pickup) > pickupRadiusKm) return false;

      // Destination proximity — only enforced for the destination-nearby mode.
      if (search.preference == MatchPreference.destinationNearby) {
        if (distanceKm(search.dropoff!, p.dropoff) > destNearbyRadiusKm) {
          return false;
        }
      }
      return true;
    }).toList();

    if (candidates.isEmpty) return const [];

    // Try forming groups starting with each individual candidate, then attempt
    // to add more candidates while constraints hold. We bias towards larger
    // (cheaper-per-rider) groups.
    final proposals = <MatchProposal>[];

    // Random-mode: shuffle so picks aren't always the same first match.
    if (search.preference == MatchPreference.randomCompatible) {
      candidates.shuffle(Random(now.microsecondsSinceEpoch));
    }

    for (final seed in candidates) {
      final group = <Passenger>[seed];
      var groupLuggage = selfLuggageSeats + LuggageRules.seatsConsumed(seed.luggage);

      // Greedy: try to add more passengers from the pool.
      for (final extra in candidates) {
        if (extra.id == seed.id) continue;
        if (group.any((g) => g.id == extra.id)) continue;

        final tentativeLuggage =
            groupLuggage + LuggageRules.seatsConsumed(extra.luggage);
        final tentativeRiders = group.length + 1 /* self */ + 1 /* extra */;

        final fitVehicle = VehicleRules.smallestThatFits(
          riders: tentativeRiders,
          luggageSeats: tentativeLuggage,
        );
        if (fitVehicle == null) continue;
        if (search.preferredVehicle != null && fitVehicle != search.preferredVehicle) {
          // Honor user's preference if they picked one.
          if (!VehicleRules.fits(
            search.preferredVehicle!,
            riders: tentativeRiders,
            luggageSeats: tentativeLuggage,
          )) {
            continue;
          }
        }

        group.add(extra);
        groupLuggage = tentativeLuggage;
      }

      final riderCount = group.length + 1; // +1 for self
      final vehicle = search.preferredVehicle ??
          VehicleRules.smallestThatFits(
            riders: riderCount,
            luggageSeats: groupLuggage,
          );
      if (vehicle == null) continue;
      if (!VehicleRules.fits(vehicle, riders: riderCount, luggageSeats: groupLuggage)) {
        continue;
      }

      proposals.add(_buildProposal(
        search: search,
        coPassengers: group,
        vehicle: vehicle,
        luggageSeats: groupLuggage,
        now: now,
      ));
    }

    // Best first: more riders → cheaper per rider; tie-break on shorter detour.
    proposals.sort((a, b) {
      final byShare = a.perRiderFare.compareTo(b.perRiderFare);
      if (byShare != 0) return byShare;
      return a.distanceKm.compareTo(b.distanceKm);
    });

    return proposals.take(maxGroupsToReturn).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Proposal construction
  // ---------------------------------------------------------------------------

  static MatchProposal _buildProposal({
    required RideSearch search,
    required List<Passenger> coPassengers,
    required VehicleType vehicle,
    required int luggageSeats,
    required DateTime now,
  }) {
    final stops = _sequenceStops(
      selfPickup: search.pickup!,
      selfDropoff: search.dropoff!,
      coPassengers: coPassengers,
    );

    // Total ride distance = sum of segment distances along the stop sequence.
    var distanceKmTotal = 0.0;
    for (var i = 1; i < stops.length; i++) {
      distanceKmTotal += distanceKm(stops[i - 1].place, stops[i].place);
    }
    final durationMin = ((distanceKmTotal / averageSpeedKmph) * 60).round();

    // Solo equivalent fare (pre-discount) and discounted group fare.
    final soloFare = fareBase + farePerKm * distanceKmTotal + farePerMin * durationMin;
    final groupFare = soloFare * (1 - shareDiscount);
    final riderCount = coPassengers.length + 1;
    final perRider = groupFare / riderCount;

    return MatchProposal(
      id: 'match_${now.microsecondsSinceEpoch}_${coPassengers.length}',
      coPassengers: coPassengers,
      stops: stops,
      vehicleType: vehicle,
      groupFare: _round(groupFare),
      perRiderFare: _round(perRider),
      distanceKm: double.parse(distanceKmTotal.toStringAsFixed(2)),
      durationMin: durationMin,
      luggageSeatsUsed: luggageSeats,
      luggageSeatsFree: vehicle.luggageCapacity - luggageSeats,
    );
  }

  /// Sequence stops as: all pickups (nearest-first from the seed pickup),
  /// then all drop-offs (nearest-first from the last pickup).
  ///
  /// This is a simple heuristic — for production swap in a routing engine
  /// (OSRM / Google Directions) that returns an optimal ordering.
  static List<RouteStop> _sequenceStops({
    required Place selfPickup,
    required Place selfDropoff,
    required List<Passenger> coPassengers,
  }) {
    final pickups = <_Pending>[
      _Pending(StopKind.pickup, selfPickup, 'self', 'You'),
      ...coPassengers.map(
        (p) => _Pending(StopKind.pickup, p.pickup, p.id, p.firstName),
      ),
    ];
    final drops = <_Pending>[
      _Pending(StopKind.dropoff, selfDropoff, 'self', 'You'),
      ...coPassengers.map(
        (p) => _Pending(StopKind.dropoff, p.dropoff, p.id, p.firstName),
      ),
    ];

    final result = <RouteStop>[];
    var cursor = pickups.first.place;
    var elapsedKm = 0.0;
    var order = 0;

    void consume(List<_Pending> bucket) {
      while (bucket.isNotEmpty) {
        bucket.sort((a, b) => distanceKm(cursor, a.place).compareTo(distanceKm(cursor, b.place)));
        final next = bucket.removeAt(0);
        elapsedKm += distanceKm(cursor, next.place);
        cursor = next.place;
        result.add(RouteStop(
          kind: next.kind,
          place: next.place,
          passengerId: next.passengerId,
          passengerFirstName: next.firstName,
          order: order++,
          etaFromStartMin: ((elapsedKm / averageSpeedKmph) * 60).round(),
        ));
      }
    }

    consume(pickups);
    consume(drops);
    return result;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(0));
}

class _Pending {
  final StopKind kind;
  final Place place;
  final String passengerId;
  final String firstName;
  _Pending(this.kind, this.place, this.passengerId, this.firstName);
}
