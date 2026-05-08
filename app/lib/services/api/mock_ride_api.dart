import 'dart:math';

import '../../models/match_proposal.dart';
import '../../models/payment.dart';
import '../../models/ride.dart';
import '../../models/ride_search.dart';
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
}
