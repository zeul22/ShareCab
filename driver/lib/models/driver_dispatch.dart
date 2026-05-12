import 'place.dart';

/// Status of an individual trip in the driver's dispatch. Mirrors the
/// backend `Trip.status` enum 1:1 — the driver-side UI only cares about
/// the four states their CTAs can act on (assigned, arriving, in_progress,
/// completed). Other rider-side states (`requested`, `matched`, `cancelled`)
/// are handled at higher layers and don't reach here.
enum DispatchStatus {
  assigned,
  arriving,
  inProgress,
  completed,
  unknown;

  static DispatchStatus parse(String? raw) {
    switch (raw) {
      case 'driver_assigned': return DispatchStatus.assigned;
      case 'arriving': return DispatchStatus.arriving;
      case 'in_progress': return DispatchStatus.inProgress;
      case 'completed': return DispatchStatus.completed;
      default: return DispatchStatus.unknown;
    }
  }

  /// Human-readable headline for the state card.
  String get label {
    switch (this) {
      case DispatchStatus.assigned: return 'Assigned';
      case DispatchStatus.arriving: return 'Arriving at pickup';
      case DispatchStatus.inProgress: return 'Trip in progress';
      case DispatchStatus.completed: return 'Completed';
      case DispatchStatus.unknown: return 'Unknown';
    }
  }
}

/// One rider in the driver's dispatch. `tripId` is the per-rider trip
/// identifier — the lifecycle endpoints (`/trips/:id/arrive` etc.) take
/// any of these ids; the backend walks the whole sibling group together.
class DispatchRider {
  final String tripId;
  final String riderId;
  final String name;
  final double rating;
  final String? phone;
  final Place pickup;
  final Place dropoff;
  final DispatchStatus status;

  /// This rider's fare in RUPEES (parsed from the backend paise field).
  /// Equal to what the rider is charged on their payment screen.
  final double fareEstimate;

  /// Driver's take-home from this rider in RUPEES = total minus the
  /// GST passthrough. Equal to `fareEstimate` until GST is enabled.
  /// Available only when the trip carries a structured breakdown
  /// (post-pricing-rewrite); falls back to `fareEstimate` otherwise.
  final double driverPayout;

  const DispatchRider({
    required this.tripId,
    required this.riderId,
    required this.name,
    required this.rating,
    required this.pickup,
    required this.dropoff,
    required this.status,
    required this.fareEstimate,
    required this.driverPayout,
    this.phone,
  });

  String get firstName {
    final n = name.trim();
    if (n.isEmpty) return 'Rider';
    return n.split(' ').first;
  }

  /// True once the driver has marked this rider as picked up. Used by the
  /// active-trip screen to decide whether the pickup stop is still pending
  /// or should be hidden from the to-do list.
  bool get pickupDone =>
      status == DispatchStatus.inProgress || status == DispatchStatus.completed;

  /// True once the driver has dropped this rider. Their stops are then
  /// fully done and they fall off the active list.
  bool get dropDone => status == DispatchStatus.completed;

  /// In the cab right now — between pickup and drop. The rider-side UI
  /// uses the same window to show "On the way to your destination".
  bool get inCab => pickupDone && !dropDone;

  factory DispatchRider.fromTripJson(Map<String, dynamic> trip) {
    final rider = trip['rider'];
    String name = '';
    double rating = 5.0;
    String riderId = '';
    String? phone;
    if (rider is Map<String, dynamic>) {
      name = (rider['name'] as String?) ?? '';
      rating = (rider['rating'] as num?)?.toDouble() ?? 5.0;
      riderId = (rider['_id'] as String?) ?? '';
      phone = rider['phone'] as String?;
    } else if (rider is String) {
      riderId = rider;
    }
    // Backend reports fare in PAISE post pricing-rewrite. Convert to
    // rupees for display. driverPayout = total minus GST passthrough;
    // pulled from the breakdown when present, otherwise = fareEstimate
    // (no GST being collected yet).
    final farePaise = (trip['fareEstimate'] as num?)?.toInt() ?? 0;
    final fareRupees = farePaise / 100.0;
    final breakdown = trip['fareBreakdown'] as Map<String, dynamic>?;
    final driverPayoutPaise =
        (breakdown?['driverPayout'] as num?)?.toInt() ?? farePaise;
    return DispatchRider(
      tripId: (trip['_id'] as String?) ?? '',
      riderId: riderId,
      name: name,
      rating: rating,
      phone: phone,
      pickup: Place.fromJson((trip['pickup'] as Map<String, dynamic>?) ?? const {}),
      dropoff: Place.fromJson((trip['dropoff'] as Map<String, dynamic>?) ?? const {}),
      status: DispatchStatus.parse(trip['status'] as String?),
      fareEstimate: fareRupees,
      driverPayout: driverPayoutPaise / 100.0,
    );
  }
}

/// One stop on the driver's optimal route. Sequenced pickup-then-dropoff
/// in [DriverDispatch.stops] — the simplest order that guarantees no rider
/// gets dropped before they're picked up. A real router (OSRM/Maps) would
/// optimise further, but this is correct.
enum DispatchStopKind { pickup, dropoff }

class DispatchStop {
  final DispatchStopKind kind;
  final Place place;
  final String tripId;
  final String riderName;

  const DispatchStop({
    required this.kind,
    required this.place,
    required this.tripId,
    required this.riderName,
  });
}

/// Aggregate view of everything dispatched to one driver right now. The
/// backend returns an array of trips; this model groups them by their
/// shared matchGroup (or treats a solo trip as a 1-rider dispatch).
///
/// Empty when the driver is online but unassigned — the caller should
/// branch on [isEmpty] rather than expecting an exception.
class DriverDispatch {
  final List<DispatchRider> riders;
  final List<DispatchStop> stops;
  final DispatchStatus status;
  final double totalFare;
  final String? matchGroupId;

  const DriverDispatch({
    required this.riders,
    required this.stops,
    required this.status,
    required this.totalFare,
    this.matchGroupId,
  });

  bool get isEmpty => riders.isEmpty;
  bool get isShared => riders.length > 1;

  /// Sum of each rider's take-home contribution. Equal to [totalFare]
  /// until GST is enabled on the platform; from there it's a few % less.
  double get totalDriverPayout =>
      riders.fold<double>(0, (a, r) => a + r.driverPayout);

  /// First trip id, used to drive bulk endpoints like `/arrive` that walk
  /// every sibling at once. Per-rider endpoints (`/picked-up`, `/dropped`)
  /// take a specific rider's `tripId` instead.
  String? get primaryTripId => riders.isEmpty ? null : riders.first.tripId;

  /// True when at least one rider is still awaiting pickup. While true,
  /// the bulk `/arrive` CTA is what the driver should see.
  bool get allAwaitingPickup =>
      riders.every((r) => r.status == DispatchStatus.assigned);

  /// True when no rider has been picked up yet but the driver is en route.
  bool get allArriving =>
      riders.every((r) => r.status == DispatchStatus.arriving);

  /// True when every rider has been dropped — group is done.
  bool get allDropped => riders.every((r) => r.dropDone);

  /// Stops still to be reached, in driving order: pending pickups first,
  /// then pending drops. Once a rider is picked up their pickup stop falls
  /// off; once dropped their drop stop falls off too. Drives the per-stop
  /// "Reached" CTAs and the geofence banner.
  List<DispatchStop> get pendingStops {
    final byTripId = {for (final r in riders) r.tripId: r};
    return [
      for (final s in stops)
        if (_isPending(s, byTripId)) s,
    ];
  }

  static bool _isPending(DispatchStop s, Map<String, DispatchRider> byTripId) {
    final r = byTripId[s.tripId];
    if (r == null) return false;
    if (s.kind == DispatchStopKind.pickup) return !r.pickupDone;
    return !r.dropDone;
  }

  /// Return whichever status is "earlier" in the lifecycle, used to
  /// summarise a divergent group as the LEAST advanced rider's state.
  static DispatchStatus _earlierStatus(DispatchStatus a, DispatchStatus b) {
    return _stage(a) <= _stage(b) ? a : b;
  }

  static int _stage(DispatchStatus s) {
    switch (s) {
      case DispatchStatus.assigned: return 0;
      case DispatchStatus.arriving: return 1;
      case DispatchStatus.inProgress: return 2;
      case DispatchStatus.completed: return 3;
      case DispatchStatus.unknown: return -1;
    }
  }

  factory DriverDispatch.fromTrips(List<dynamic> tripsJson) {
    if (tripsJson.isEmpty) {
      return const DriverDispatch(
        riders: [],
        stops: [],
        status: DispatchStatus.unknown,
        totalFare: 0,
      );
    }

    final riders = tripsJson
        .whereType<Map<String, dynamic>>()
        .map(DispatchRider.fromTripJson)
        .toList(growable: false);

    final first = tripsJson.first as Map<String, dynamic>;
    final groupRaw = first['matchGroup'];
    String? groupId;
    if (groupRaw is String) {
      groupId = groupRaw;
    } else if (groupRaw is Map<String, dynamic>) {
      groupId = groupRaw['_id'] as String?;
    }

    // With per-rider lifecycle, sibling statuses can diverge (one rider
    // dropped, another still in cab). Surface the LEAST advanced status
    // as the group-level summary, so the home screen's banner reads as
    // "Arriving" until everyone's been picked up, "In progress" until
    // everyone's been dropped, etc.
    final status = riders
        .map((r) => r.status)
        .reduce((a, b) => _earlierStatus(a, b));

    // Total fare to collect: sum of per-trip fareEstimate. For shared
    // trips, the backend's settlement applies the shared discount on
    // completion; the *displayed* total here is what the driver should
    // collect from all riders combined.
    final totalFare = riders.fold<double>(0, (a, r) => a + r.fareEstimate);

    // Build stops: all pickups first (in whatever order the backend
    // returned them), then all dropoffs. Guarantees no rider is dropped
    // before pickup. Future: integrate Maps Directions API for an
    // actually-optimal sequence.
    final stops = <DispatchStop>[
      for (final r in riders)
        DispatchStop(
          kind: DispatchStopKind.pickup,
          place: r.pickup,
          tripId: r.tripId,
          riderName: r.firstName,
        ),
      for (final r in riders)
        DispatchStop(
          kind: DispatchStopKind.dropoff,
          place: r.dropoff,
          tripId: r.tripId,
          riderName: r.firstName,
        ),
    ];

    return DriverDispatch(
      riders: riders,
      stops: stops,
      status: status,
      totalFare: totalFare,
      matchGroupId: groupId,
    );
  }
}
