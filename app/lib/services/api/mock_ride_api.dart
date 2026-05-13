import 'dart:math';

import '../../models/driver_live_location.dart';
import '../../models/match_proposal.dart';
import '../../models/payment.dart';
import '../../models/pending_co_rider_rating.dart';
import '../../models/recent_destination.dart';
import '../../models/ride.dart';
import '../../models/ride_search.dart';
import '../../models/route_stop.dart';
import '../matching/matching_engine.dart';
import 'mock_data.dart';
import 'ride_api.dart';

/// In-memory implementation of [RideApi]. Uses the real [MatchingEngine] over
/// a static fixture pool so the UI flow is deterministic and testable.
///
/// Latency is simulated so loading states can be exercised. None of this is
/// persisted — restarting the app clears history.
class MockRideApi implements RideApi {
  final Random _rng = Random();
  final List<Ride> _history = [];
  Ride? _activeRide;

  Duration _latency() => Duration(milliseconds: 350 + _rng.nextInt(450));

  @override
  Future<String> createSearchSession(RideSearch search) async {
    await Future.delayed(_latency());
    return 'sess_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<MatchProposal>> findDestinationMatches(
    String sessionId,
    RideSearch search,
  ) async {
    await Future.delayed(_latency());
    return MatchingEngine.findGroups(
      search: search.copyWith(),
      pool: MockData.activeSearchPool(),
      now: DateTime.now(),
    );
  }

  @override
  Future<List<MatchProposal>> findRandomMatches(
    String sessionId,
    RideSearch search,
  ) async {
    await Future.delayed(_latency());
    // Force the random-mode preference so the engine widens its candidate set.
    return MatchingEngine.findGroups(
      search: search.copyWith(preference: search.preference),
      pool: MockData.activeSearchPool(),
      now: DateTime.now(),
    );
  }

  @override
  Future<Ride> acceptMatch(String sessionId, MatchProposal proposal) async {
    await Future.delayed(_latency());
    final driver = MockData.pickDriverForType(proposal.vehicleType);
    final ride = Ride(
      id: 'ride_${DateTime.now().microsecondsSinceEpoch}',
      proposal: proposal,
      driver: driver,
      otp: MockData.generateOtp(_rng),
      status: RideStatus.confirmed,
      confirmedAt: DateTime.now(),
      riders: proposal.coPassengers,
      perRiderFare: proposal.perRiderFare,
    );
    _activeRide = ride;
    return ride;
  }

  @override
  Future<void> rejectMatch(String sessionId, MatchProposal proposal) async {
    await Future.delayed(_latency());
    // No-op for mock — proposal returned to pool conceptually.
  }

  @override
  Future<Ride> verifyOtp(String rideId, String otp) async {
    await Future.delayed(_latency());
    final ride = _activeRide;
    if (ride == null) {
      throw StateError('No active ride to verify');
    }
    if (otp != ride.otp) {
      throw ArgumentError('OTP mismatch');
    }
    final updated = ride.copyWith(status: RideStatus.inProgress, startedAt: DateTime.now());
    _activeRide = updated;
    return updated;
  }

  @override
  Future<Ride> getLiveRide(String rideId) async {
    await Future.delayed(_latency());
    final ride = _activeRide;
    if (ride == null || ride.id != rideId) {
      throw StateError('Ride $rideId not found');
    }
    return ride;
  }

  @override
  Future<Ride?> getActiveRide() async {
    // Mock keeps no cross-session state — there's never an active ride to resume.
    await Future.delayed(_latency());
    return _activeRide;
  }

  /// Test/UI helper to force-complete the active ride (e.g. from the Live
  /// screen's "I've reached" affordance).
  Future<Ride> completeActiveRide() async {
    final ride = _activeRide;
    if (ride == null) throw StateError('No active ride');
    final completed = ride.copyWith(
      status: RideStatus.completed,
      completedAt: DateTime.now(),
    );
    _activeRide = null;
    _history.insert(0, completed);
    return completed;
  }

  @override
  Future<Payment> completePayment(Payment payment) async {
    await Future.delayed(_latency());
    return payment.copyWith(status: PaymentStatus.paid, paidAt: DateTime.now());
  }

  @override
  Future<List<Ride>> getRideHistory() async {
    await Future.delayed(_latency());
    return List.unmodifiable(_history);
  }

  @override
  Future<List<RecentDestination>> getRecentDestinations({int limit = 5}) async {
    await Future.delayed(_latency());
    // Dedup by rounded lat/lng (mirrors the backend's 4-decimal bucket)
    // and surface the most-recent entry per bucket with a frequency count.
    // The rider's own drop is the stop with passengerId 'me' and
    // kind == dropoff (see http_ride_api when it composes the proposal).
    final buckets = <String, RecentDestination>{};
    for (final ride in _history) {
      RouteStop? drop;
      for (final s in ride.proposal.stops) {
        if (s.kind == StopKind.dropoff && s.passengerId == 'me') {
          drop = s;
          break;
        }
      }
      // Fallback for older mock data that didn't tag the 'me' stop.
      drop ??= ride.proposal.stops.lastWhere(
        (s) => s.kind == StopKind.dropoff,
        orElse: () => ride.proposal.stops.last,
      );
      final p = drop.place;
      final key = '${p.lat.toStringAsFixed(4)},${p.lng.toStringAsFixed(4)}';
      final existing = buckets[key];
      buckets[key] = RecentDestination(
        address: p.address,
        lat: p.lat,
        lng: p.lng,
        lastUsedAt: ride.completedAt ?? ride.confirmedAt,
        tripCount: (existing?.tripCount ?? 0) + 1,
      );
    }
    final sorted = buckets.values.toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return sorted.take(limit.clamp(1, 20)).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Mock unlock flow — no-op success for all three. The mock backend
  // doesn't actually gate matches behind unlocks, so the UI can show
  // the full sheet flow without needing real ads or payment.
  // ---------------------------------------------------------------------------

  @override
  Future<void> recordAdRewardForUnlock({required int adsCompleted}) async {
    await Future.delayed(_latency());
  }

  @override
  Future<void> recordPaymentForUnlock({
    required int amountPaise,
    String? orderId,
    required String paymentRef,
    String? signature,
  }) async {
    await Future.delayed(_latency());
  }

  @override
  Future<UnlockOrder> startUnlockOrder() async {
    await Future.delayed(_latency());
    return UnlockOrder(
      orderId: 'mock_order_${DateTime.now().millisecondsSinceEpoch}',
      amountPaise: 5000,
      currency: 'INR',
      razorpayKeyId: '', // empty = stub-mode signal, mock-app skips the sheet
    );
  }

  @override
  Future<void> unlockMatchForTrip(String tripId) async {
    await Future.delayed(_latency());
  }

  @override
  Future<Ride> findCabForTrip(String tripId) async {
    await Future.delayed(_latency());
    // Mock backend has no real dispatch — just return whatever active
    // ride we already have so the caller's UI flow keeps working.
    final ride = _activeRide;
    if (ride == null) {
      throw StateError('No active ride for $tripId');
    }
    return ride;
  }

  @override
  Future<void> closeRiderTrip(String tripId) async {
    await Future.delayed(_latency());
    // Mock impl: drop the now-closed trip from history so the rider's
    // next session sees a clean slate. Real backend marks it completed.
    _history.removeWhere((r) => r.id == tripId);
  }

  @override
  Future<void> endRideEarly(String tripId) async {
    await Future.delayed(_latency());
    // Mock impl: same shape as closeRiderTrip — the real backend marks
    // completed + charges fareFinal=fareEstimate. The mock just drops it.
    _history.removeWhere((r) => r.id == tripId);
  }

  @override
  Future<DriverLocationResponse> getDriverLocation(String tripId) async {
    await Future.delayed(_latency());
    // Mock impl: jiggle around a Bangalore coord so the rider-side
    // tracker test path renders something. ETA fixed at 4 min.
    final jitter = (DateTime.now().millisecondsSinceEpoch % 1000) / 1000000;
    return DriverLocationResponse(
      driver: DriverLiveLocation(
        lat: 12.9716 + jitter,
        lng: 77.5946 + jitter,
        updatedAt: DateTime.now(),
      ),
      eta: const TripEta(
        toStop: 'pickup',
        seconds: 240,
        distanceMeters: 1800,
        source: 'haversine',
      ),
    );
  }

  @override
  Future<String?> reverseGeocode({required double lat, required double lng}) async {
    await Future.delayed(_latency());
    // Mock impl: stable name so the offline / demo flow renders
    // something sensible rather than a coord string. Real backend
    // hits Google Maps via geocodingService.
    return 'Indiranagar, Bengaluru';
  }

  @override
  Future<List<PendingCoRiderRating>> getPendingCoRiderRatings() async {
    await Future.delayed(_latency());
    // Mock impl: no pending rating prompts. The auto-prompt flow is
    // exercised against the real backend; the mock stays quiet so
    // demo / screenshot runs aren't constantly popping the dialog.
    return const [];
  }

  @override
  Future<void> rateCoRider({
    required String tripId,
    required String coRiderUserId,
    required int stars,
    String? comment,
  }) async {
    await Future.delayed(_latency());
  }

  @override
  Future<void> skipCoRiderRating({
    required String tripId,
    required String coRiderUserId,
  }) async {
    await Future.delayed(_latency());
  }
}
