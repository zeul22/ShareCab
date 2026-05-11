import '../../models/match_proposal.dart';
import '../../models/payment.dart';
import '../../models/recent_destination.dart';
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

  /// Recent unique destinations the rider has dropped at (deduped by
  /// rounded lat/lng server-side). Powers the "tap to repeat" shortcut
  /// on the destination screen. [limit] is clamped to [1, 20] by the
  /// backend; default 5.
  Future<List<RecentDestination>> getRecentDestinations({int limit = 5});

  // ---------------------------------------------------------------------------
  // Unlock-gate flow (rider-only mode). After a match is found, the
  // rider has to either watch enough rewarded ads or pay to reveal the
  // co-rider's details. These methods speak to the backend's existing
  // /unlocks/* endpoints (which mint an Unlock document) and the new
  // /trips/:id/unlock-match endpoint (which consumes it).
  // ---------------------------------------------------------------------------

  /// Tell the backend the rider has completed [adsCompleted] rewarded
  /// ads. Backend re-checks against the rider's rating tier (top tier
  /// needs 1 ad, default 2, low-rated 3) and mints an Unlock if the
  /// count is enough — otherwise returns 400 with the required count.
  Future<void> recordAdRewardForUnlock({required int adsCompleted});

  /// Stub Razorpay payment path: tells the backend "rider paid X paise"
  /// and the backend mints an Unlock. In real Razorpay mode, callers
  /// pass the orderId + paymentId + signature returned by the checkout
  /// SDK; in stub mode (no keys), the signature check is a no-op so
  /// the demo flow works without a Razorpay account.
  Future<void> recordPaymentForUnlock({
    required int amountPaise,
    String? orderId,
    required String paymentRef,
    String? signature,
  });

  /// Consume one of the rider's unlocks against this matched trip,
  /// revealing co-rider details. Idempotent. 402 if no unlock available,
  /// 409 if there's no match yet on this trip.
  Future<void> unlockMatchForTrip(String tripId);

  /// Rider-only mode: the rider self-closes a matched trip after
  /// they've arranged their own cab off-platform (Uber, Ola, etc.).
  /// Sets fareFinal=0, marks completed, settles the group when the
  /// last sibling closes too. Idempotent. 409 outside rider-only mode.
  Future<void> closeRiderTrip(String tripId);
}
