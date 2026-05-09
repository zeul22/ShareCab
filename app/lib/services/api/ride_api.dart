import '../../models/match_proposal.dart';
import '../../models/payment.dart';
import '../../models/ride.dart';
import '../../models/ride_search.dart';

/// Backend-agnostic interface. Today there's one implementation
/// (`MockRideApi`); when the real backend is wired up, write a `HttpRideApi`
/// that satisfies this contract and swap the binding in `main.dart`.
abstract class RideApi {
  /// Persist the user's in-progress search and start a server-side session.
  /// Returns a session id the client can pass to subsequent calls.
  Future<String> createSearchSession(RideSearch search);

  /// Look for compatible groups whose destinations are within ~2-4 km.
  Future<List<MatchProposal>> findDestinationMatches(String sessionId, RideSearch search);

  /// Look for any compatible group (route, capacity, luggage all OK).
  Future<List<MatchProposal>> findRandomMatches(String sessionId, RideSearch search);

  /// User accepted a proposal — confirm it and lock in a driver + OTP.
  Future<Ride> acceptMatch(String sessionId, MatchProposal proposal);

  /// User rejected a proposal — release it; backend may keep them in the pool.
  Future<void> rejectMatch(String sessionId, MatchProposal proposal);

  /// Verify the OTP at pickup. Returns the updated ride.
  Future<Ride> verifyOtp(String rideId, String otp);

  /// Latest snapshot of an in-flight ride (for polling fallback / refresh).
  Future<Ride> getLiveRide(String rideId);

  /// Returns the rider's currently in-flight ride, if any. Used on cold start
  /// to restore the in-progress flow when the user reopens the app. Returns
  /// null when the rider has no active ride.
  Future<Ride?> getActiveRide();

  /// Mark a payment as paid (mock — real impl would talk to the gateway).
  Future<Payment> completePayment(Payment payment);

  /// All rides this user has taken (newest first).
  Future<List<Ride>> getRideHistory();
}
