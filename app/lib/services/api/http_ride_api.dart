import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/driver.dart';
import '../../models/luggage.dart';
import '../../models/match_proposal.dart';
import '../../models/passenger.dart';
import '../../models/payment.dart';
import '../../models/place.dart';
import '../../models/recent_destination.dart';
import '../../models/ride.dart';
import '../../models/ride_search.dart';
import '../../models/route_stop.dart';
import '../../models/vehicle.dart';
import '../../utils/api_config.dart';
import 'ride_api.dart';

typedef AsyncTokenGetter = Future<String?> Function();
typedef RiderIdGetter = String? Function();

/// HTTP implementation of [RideApi] — talks to ShareCab backend at
/// `${ApiConfig.apiRoot}/trips`, `/unlocks`, etc.
///
/// The mapping between app + backend models is non-trivial:
///
/// | App                | Backend                                            |
/// |--------------------|----------------------------------------------------|
/// | `RideSearch`       | trip request body `{pickup, dropoff, shareEnabled}`|
/// | `MatchProposal`    | `Trip` + populated `MatchGroup` (one per trip)     |
/// | `Ride`             | `Trip` post-dispatch (driver assigned)             |
/// | `Driver`           | backend `Driver` doc + populated `User` for name   |
///
/// Search-session is purely client-side; the backend treats every trip as
/// its own atomic request → match → dispatch sequence.
class HttpRideApi implements RideApi {
  final http.Client _client;
  final String _root;
  final AsyncTokenGetter _tokenGetter;
  final RiderIdGetter _riderIdGetter;

  /// In-memory map of {clientSessionId → backend trip._id}, set when
  /// findDestinationMatches creates the trip and read by acceptMatch /
  /// rejectMatch. Lets the app keep its session-id abstraction without
  /// the backend having to know about sessions.
  final Map<String, String> _sessionToTripId = {};

  /// Client-generated 4-digit "OTP" per ride, since the backend doesn't
  /// emit one. Real prod should mint this server-side at trip-create time.
  final Map<String, String> _rideOtps = {};

  HttpRideApi({
    required AsyncTokenGetter tokenGetter,
    required RiderIdGetter riderIdGetter,
    http.Client? client,
    String? apiRoot,
  })  : _client = client ?? http.Client(),
        _root = apiRoot ?? ApiConfig.apiRoot,
        _tokenGetter = tokenGetter,
        _riderIdGetter = riderIdGetter;

  // ---------------------------------------------------------------------------
  // RideApi surface
  // ---------------------------------------------------------------------------

  @override
  Future<String> createSearchSession(RideSearch search) async {
    // Backend has no session concept. Generate a local id; the trip is
    // actually created in findDestinationMatches.
    return 'session_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<MatchProposal>> findDestinationMatches(
    String sessionId,
    RideSearch search,
  ) async {
    if (!search.isReadyToSearch) return const [];

    // Mint an unlock first (backend gates shareEnabled=true on this).
    // Real prod would only run after the rider watched 2 rewarded ads OR
    // completed a Razorpay payment.
    await _mintAdUnlockForCurrentRider();

    // Create the trip and return the initial state immediately. The caller
    // (RideFlowState / SearchingScreen) is responsible for polling via
    // [getLiveRide] until either the proposal's riderCount goes >=2 (match
    // found) or its 5-minute search window times out. Doing the polling
    // upstream keeps cancellation natural and lets the screen drive a
    // progress bar without a blocking RPC.
    final created = await _createTrip(search, shareEnabled: true);
    final tripId = created['_id'] as String;
    _sessionToTripId[sessionId] = tripId;

    // Always return one proposal — riderCount tells the caller whether it
    // landed a match (>=2) or is still pending (==1).
    final proposal = _buildProposalFromTrip(created, search);
    return [proposal];
  }

  @override
  Future<List<MatchProposal>> findRandomMatches(
    String sessionId,
    RideSearch search,
  ) =>
      // Backend's matching rule is the same regardless of preference (radii
      // come from env, not from the request). Same flow either way.
      findDestinationMatches(sessionId, search);

  @override
  Future<Ride> acceptMatch(String sessionId, MatchProposal proposal) async {
    // Trip is already created and dispatched. Just refresh and convert.
    final trip = await _getTrip(proposal.id);
    return _buildRideFromTrip(trip);
  }

  @override
  Future<void> rejectMatch(String sessionId, MatchProposal proposal) async {
    await _cancelTrip(proposal.id);
    _sessionToTripId.remove(sessionId);
  }

  @override
  Future<Ride> verifyOtp(String rideId, String otp) async {
    // No backend OTP flow yet (the driver-side /start endpoint advances the
    // lifecycle, not the rider). For now we sanity-check against the
    // client-stored OTP and return the live trip; the driver's app would
    // call /api/trips/:id/start to actually flip the status.
    final expected = _rideOtps[rideId];
    if (expected != null && otp != expected) {
      throw Exception('OTP mismatch — expected $expected');
    }
    final trip = await _getTrip(rideId);
    return _buildRideFromTrip(trip);
  }

  @override
  Future<Ride> getLiveRide(String rideId) async {
    final trip = await _getTrip(rideId);
    return _buildRideFromTrip(trip);
  }

  @override
  Future<Ride?> getActiveRide() async {
    final res = await _get('/trips/mine/active', auth: true);
    final body = _decode(res);
    final trip = body['trip'];
    if (trip == null) return null;
    return _buildRideFromTrip(trip as Map<String, dynamic>);
  }

  @override
  Future<Payment> completePayment(Payment payment) async {
    // Backend marks `fareFinal` automatically when the driver hits /complete.
    // Client-side we just acknowledge — real prod will route through Razorpay.
    return payment.copyWith(status: PaymentStatus.paid, paidAt: DateTime.now());
  }

  @override
  Future<List<Ride>> getRideHistory() async {
    final trips = await _getMyTrips();
    return trips.map(_buildRideFromTrip).toList(growable: false);
  }

  @override
  Future<List<RecentDestination>> getRecentDestinations({int limit = 5}) async {
    final res = await _get(
      '/trips/destinations/recent?limit=$limit',
      auth: true,
    );
    final body = _decode(res);
    final arr = (body['destinations'] as List?) ?? const [];
    return arr
        .whereType<Map<String, dynamic>>()
        .map(RecentDestination.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> recordAdRewardForUnlock({required int adsCompleted}) async {
    final riderId = _riderIdGetter();
    if (riderId == null) {
      throw Exception('Not signed in — cannot record ad reward');
    }
    await _post('/unlocks/ad-reward', {
      'riderId': riderId,
      'adsCompleted': adsCompleted,
      // Per-attempt nonce so the eventual AdMob SSV path can dedupe.
      // Today the backend doesn't store this, but it's cheap to send.
      'externalRef': 'app-${DateTime.now().millisecondsSinceEpoch}',
    });
  }

  @override
  Future<void> recordPaymentForUnlock({
    required int amountPaise,
    String? orderId,
    required String paymentRef,
    String? signature,
  }) async {
    final riderId = _riderIdGetter();
    if (riderId == null) {
      throw Exception('Not signed in — cannot record payment');
    }
    await _post('/unlocks/payment-confirm', {
      'riderId': riderId,
      if (orderId != null) 'orderId': orderId,
      'externalRef': paymentRef,
      'amountPaise': amountPaise,
      if (signature != null) 'signature': signature,
    });
  }

  @override
  Future<void> unlockMatchForTrip(String tripId) async {
    await _post('/trips/$tripId/unlock-match', const {}, auth: true);
  }

  @override
  Future<void> closeRiderTrip(String tripId) async {
    await _post('/trips/$tripId/rider-close', const {}, auth: true);
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _createTrip(RideSearch search, {required bool shareEnabled}) async {
    final res = await _post(
      '/trips/',
      {
        'pickup': {
          'address': search.pickup!.address,
          'lat': search.pickup!.lat,
          'lng': search.pickup!.lng,
        },
        'dropoff': {
          'address': search.dropoff!.address,
          'lat': search.dropoff!.lat,
          'lng': search.dropoff!.lng,
        },
        'shareEnabled': shareEnabled,
      },
      auth: true,
    );
    return _decode(res)['trip'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _getTrip(String tripId) async {
    final res = await _get('/trips/$tripId', auth: true);
    return _decode(res)['trip'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _getMyTrips() async {
    final res = await _get('/trips/mine', auth: true);
    final arr = (_decode(res)['trips'] as List?) ?? const [];
    return arr.cast<Map<String, dynamic>>();
  }

  Future<void> _cancelTrip(String tripId) async {
    await _post('/trips/$tripId/cancel', const {}, auth: true);
  }

  Future<void> _mintAdUnlockForCurrentRider() async {
    final riderId = _riderIdGetter();
    if (riderId == null) {
      throw Exception('Not signed in — cannot mint unlock');
    }
    await _post('/unlocks/ad-reward', {
      'riderId': riderId,
      'adsCompleted': 2,
      'externalRef': 'app-${DateTime.now().millisecondsSinceEpoch}',
    });
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final headers = await _headers(auth: auth);
    final res = await _client.post(
      Uri.parse('$_root$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _RideException.fromResponse(res);
    }
    return res;
  }

  Future<http.Response> _get(String path, {bool auth = false}) async {
    final headers = await _headers(auth: auth);
    final res = await _client.get(Uri.parse('$_root$path'), headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _RideException.fromResponse(res);
    }
    return res;
  }

  Future<Map<String, String>> _headers({required bool auth}) async {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await _tokenGetter();
      if (token == null) {
        throw Exception('Not signed in — cannot call authenticated endpoint');
      }
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Backend → app model mapping
  // ---------------------------------------------------------------------------

  /// Build a [MatchProposal] from a resolved trip. Two shapes:
  ///   - Trip is in a MatchGroup → proposal lists the co-rider(s).
  ///   - Trip is solo (no group, just a driver) → proposal lists only this rider.
  MatchProposal _buildProposalFromTrip(Map<String, dynamic> trip, RideSearch search) {
    final tripId = trip['_id'] as String;
    final group = trip['matchGroup'] as Map<String, dynamic>?;
    final driver = trip['driver'] as Map<String, dynamic>?;
    final vehicleType = _vehicleTypeFromCapacity(driver?['vehicle']?['capacity'] as num?);

    final coPassengers = <Passenger>[];
    // In rider-only mode the backend hides sibling details until the
    // unlock is consumed — siblings come back as `{_id, status, redacted: true}`.
    // We surface that to the UI via `gatedUnlock` so the MatchResultScreen
    // can show the unlock sheet instead of placeholder names.
    bool gatedUnlock = false;

    if (group != null) {
      // Backend deep-populates matchGroup.trips with each sibling's rider
      // name + pickup/dropoff. Use those real values; only fall back to the
      // current rider's search context if a sibling somehow comes back as
      // a bare ObjectId (defensive — shouldn't happen with TRIP_POPULATE).
      final siblingTrips = (group['trips'] as List?) ?? const [];
      for (final raw in siblingTrips) {
        if (raw is! Map<String, dynamic>) continue; // bare id; unexpected
        final siblingId = raw['_id'] as String? ?? '';
        if (siblingId == tripId) continue; // skip ourselves

        // Redaction signal — backend strips rider/pickup/dropoff and
        // tags `redacted: true` when the unlock hasn't been consumed.
        if (raw['redacted'] == true) {
          gatedUnlock = true;
          // Still record a placeholder passenger so the UI knows the
          // count of co-riders without revealing identity.
          coPassengers.add(Passenger(
            id: siblingId.isNotEmpty ? siblingId : 'co_${coPassengers.length}',
            firstName: 'Co-rider',
            rating: 5.0,
            pickup: search.pickup!,
            dropoff: search.dropoff!,
            luggage: LuggageProfile.empty,
          ));
          continue;
        }

        // The rider field may be a populated user doc or a bare ObjectId
        // string depending on backend selection. Both are handled.
        String firstName = 'Co-rider';
        double rating = 5.0;
        final rider = raw['rider'];
        if (rider is Map<String, dynamic>) {
          final fullName = (rider['name'] as String? ?? '').trim();
          if (fullName.isNotEmpty) firstName = fullName.split(' ').first;
          rating = (rider['rating'] as num?)?.toDouble() ?? 5.0;
        }

        coPassengers.add(Passenger(
          id: siblingId.isNotEmpty ? siblingId : 'co_${coPassengers.length}',
          firstName: firstName,
          rating: rating,
          pickup: _placeFromTripField(raw['pickup']) ?? search.pickup!,
          dropoff: _placeFromTripField(raw['dropoff']) ?? search.dropoff!,
          luggage: LuggageProfile.empty,
        ));
      }
    }

    // Build stops: current rider's pickup → all co-rider pickups → all drops.
    // Order/ETAs are placeholders (the backend doesn't currently sequence
    // route stops; a real router would populate them).
    final stops = <RouteStop>[
      RouteStop(
        kind: StopKind.pickup,
        place: search.pickup!,
        passengerId: 'me',
        passengerFirstName: 'You',
        order: 0,
        etaFromStartMin: 0,
      ),
    ];
    for (var i = 0; i < coPassengers.length; i++) {
      final p = coPassengers[i];
      stops.add(RouteStop(
        kind: StopKind.pickup,
        place: p.pickup,
        passengerId: p.id,
        passengerFirstName: p.firstName,
        order: i + 1,
        etaFromStartMin: (i + 1) * 2,
      ));
    }
    stops.add(RouteStop(
      kind: StopKind.dropoff,
      place: search.dropoff!,
      passengerId: 'me',
      passengerFirstName: 'You',
      order: stops.length,
      etaFromStartMin: 0,
    ));
    for (var i = 0; i < coPassengers.length; i++) {
      final p = coPassengers[i];
      stops.add(RouteStop(
        kind: StopKind.dropoff,
        place: p.dropoff,
        passengerId: p.id,
        passengerFirstName: p.firstName,
        order: stops.length,
        etaFromStartMin: 0,
      ));
    }

    final fareEstimate = (trip['fareEstimate'] as num?)?.toDouble() ?? 0.0;
    final distanceKm = (trip['distanceKm'] as num?)?.toDouble() ?? 0.0;
    final durationMin = (trip['durationMin'] as num?)?.toInt() ?? 0;
    final riderCount = coPassengers.length + 1;
    // Apply the same 30% share discount the backend computes when settling.
    final groupFare = riderCount > 1 ? fareEstimate * 0.7 * riderCount : fareEstimate;
    final perRiderFare = groupFare / riderCount;

    return MatchProposal(
      id: tripId,
      groupId: group?['_id'] as String?,
      coPassengers: coPassengers,
      stops: stops,
      vehicleType: vehicleType,
      groupFare: groupFare,
      perRiderFare: perRiderFare,
      distanceKm: distanceKm,
      durationMin: durationMin,
      luggageSeatsUsed: 0,
      luggageSeatsFree: vehicleType.luggageCapacity,
      gatedUnlock: gatedUnlock,
    );
  }

  Ride _buildRideFromTrip(Map<String, dynamic> trip) {
    final tripId = trip['_id'] as String;
    final driverDoc = trip['driver'] as Map<String, dynamic>?;
    final search = RideSearch(
      pickup: Place.fromJson(trip['pickup'] as Map<String, dynamic>),
      dropoff: Place.fromJson(trip['dropoff'] as Map<String, dynamic>),
      startedAt: DateTime.now(),
    );
    final proposal = _buildProposalFromTrip(trip, search);
    final driver = _driverFromBackend(driverDoc, vehicleType: proposal.vehicleType);

    final otp = _rideOtps.putIfAbsent(
      tripId,
      () => _generateOtp(),
    );

    return Ride(
      id: tripId,
      proposal: proposal,
      driver: driver,
      otp: otp,
      status: _statusFromBackend(trip['status'] as String? ?? 'requested'),
      confirmedAt: DateTime.tryParse(trip['createdAt'] as String? ?? '') ?? DateTime.now(),
      startedAt: trip['startedAt'] != null
          ? DateTime.tryParse(trip['startedAt'] as String)
          : null,
      completedAt: trip['completedAt'] != null
          ? DateTime.tryParse(trip['completedAt'] as String)
          : null,
      riders: const [],
      perRiderFare: proposal.perRiderFare,
    );
  }

  Driver _driverFromBackend(
    Map<String, dynamic>? driverDoc, {
    required VehicleType vehicleType,
  }) {
    if (driverDoc == null) {
      return const Driver(
        id: '',
        name: 'Awaiting driver',
        phoneMasked: '',
        rating: 0,
        totalRides: 0,
        vehicle: Vehicle(
          id: '',
          type: VehicleType.sedan,
          model: '',
          plate: '',
          color: '',
        ),
      );
    }
    final v = driverDoc['vehicle'] as Map<String, dynamic>? ?? const {};
    return Driver(
      id: driverDoc['_id'] as String? ?? '',
      // Backend doesn't populate the user on driver — we'd need a join. For
      // the demo we surface the plate as a stand-in name.
      name: 'Driver ${(v['plate'] as String? ?? '').toUpperCase()}',
      phoneMasked: '',
      rating: 5.0,
      totalRides: 0,
      vehicle: Vehicle(
        id: driverDoc['_id'] as String? ?? '',
        type: vehicleType,
        model: v['model'] as String? ?? '',
        plate: v['plate'] as String? ?? '',
        color: v['color'] as String? ?? '',
      ),
    );
  }

  /// Convert a backend `trip.pickup` / `trip.dropoff` subdocument into a
  /// [Place]. The backend stores location as GeoJSON `{type: 'Point',
  /// coordinates: [lng, lat]}` and an optional `address` string — `Place.fromJson`
  /// already handles that shape. Returns null if the field is missing or
  /// malformed (we then fall back to the current rider's own search context
  /// in the caller).
  Place? _placeFromTripField(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      return Place.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  VehicleType _vehicleTypeFromCapacity(num? capacity) {
    final c = capacity?.toInt() ?? 4;
    if (c >= 6) return VehicleType.suv;
    if (c >= 4) return VehicleType.sedan;
    return VehicleType.hatchback;
  }

  RideStatus _statusFromBackend(String status) {
    switch (status) {
      case 'requested':
      case 'matched':
      case 'driver_assigned':
        return RideStatus.confirmed;
      case 'arriving':
        return RideStatus.arriving;
      case 'in_progress':
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled':
        return RideStatus.cancelled;
      default:
        return RideStatus.confirmed;
    }
  }

  String _generateOtp() {
    final n = DateTime.now().microsecondsSinceEpoch % 10000;
    return n.toString().padLeft(4, '0');
  }
}

class _RideException implements Exception {
  final int statusCode;
  final String message;

  const _RideException(this.statusCode, this.message);

  factory _RideException.fromResponse(http.Response res) {
    String message = 'Ride API ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final m = body['error'] as String?;
      if (m != null) message = m;
    } catch (_) {/* keep default */}
    return _RideException(res.statusCode, message);
  }

  @override
  String toString() => message;
}
