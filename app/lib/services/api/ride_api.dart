import '../../models/driver_live_location.dart';
import '../../models/match_proposal.dart';
import '../../models/payment.dart';
import '../../models/pending_co_rider_rating.dart';
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

  /// Step 1 of the Razorpay-backed unlock pay path. Backend creates an
  /// order tagged `notes.kind=rider_unlock`. The client feeds the
  /// returned [orderId] / [razorpayKeyId] / [amountPaise] into the
  /// checkout sheet; on success, signature + paymentId come back via
  /// [recordPaymentForUnlock]. When [razorpayKeyId] is empty, the
  /// backend is in stub mode and the client should bypass the sheet.
  Future<UnlockOrder> startUnlockOrder();

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

  /// Rider taps "Find Cab" — explicit consent to start driver dispatch.
  /// In a shared trip, both riders must call this; the backend only
  /// fires the offer once everyone in the matchGroup is ready. Returns
  /// the refreshed trip so the caller can read `status` + sibling
  /// `readyToFindCab` to render "waiting for co-rider" if needed.
  /// 409 if status != 'matched'.
  Future<Ride> findCabForTrip(String tripId);

  /// Rider-only mode: the rider self-closes a matched trip after
  /// they've arranged their own cab off-platform (Uber, Ola, etc.).
  /// Sets fareFinal=0, marks completed, settles the group when the
  /// last sibling closes too. Idempotent. 409 outside rider-only mode.
  Future<void> closeRiderTrip(String tripId);

  /// Driver-dispatch mode: rider stops the ride at their current location
  /// while it's `in_progress`. Charges the FULL pre-quoted fare — no
  /// proration. Pulls the trip from the driver's activeTrips; siblings
  /// in a shared cab keep going. Idempotent. 409 outside `in_progress`.
  Future<void> endRideEarly(String tripId);

  /// Live driver position + ETA to the next pending stop. Used by
  /// [TripTrackingService] to drive the live-ride screen's driver marker
  /// + ETA chip. Polled every 5s during `arriving` / `in_progress`.
  /// Throws when no driver is assigned yet (404) or the driver hasn't
  /// pushed any location since coming online.
  Future<DriverLocationResponse> getDriverLocation(String tripId);

  /// Reverse-geocode `(lat, lng)` to a short human-readable place name
  /// (e.g. "Indiranagar, Bengaluru"). Used by [LocationService] the
  /// moment a current-location pin is captured so the trip is persisted
  /// with a meaningful pickup address — ride history and analytics
  /// then surface real names instead of every row reading "Current
  /// location". Returns null on any error so callers can fall back.
  Future<String?> reverseGeocode({required double lat, required double lng});

  // ---------------------------------------------------------------------------
  // Co-rider rating flow.
  //
  // Effective rating math (backend-enforced, mirrored in docs):
  //   rating = clamp(avg(received Ratings.stars) - 0.25 * count(my skips), 1, 5)
  //
  // Endpoints below are idempotent per (trip, fromUser, toUser) — repeat
  // calls return 409. The rider app's polling watcher fetches pending
  // entries on every tick, opens a CoRiderRatingDialog, and either rates
  // or explicitly skips. Dismissing the dialog without choosing leaves
  // the entry pending for the next prompt.
  // ---------------------------------------------------------------------------

  /// List co-riders this user still owes a rate-or-skip decision on.
  /// Server-side filter excludes already-rated, already-skipped, and
  /// trips older than 7d. Empty list when nothing pending.
  Future<List<PendingCoRiderRating>> getPendingCoRiderRatings();

  /// Submit a star rating for a co-rider. Server rejects if the
  /// co-rider's leg hasn't completed yet, or if the pair was already
  /// rated / skipped (409).
  Future<void> rateCoRider({
    required String tripId,
    required String coRiderUserId,
    required int stars,
    String? comment,
  });

  /// Explicitly skip rating a co-rider. Applies a -0.25 penalty to
  /// THIS rider's own rating (floored at 1.0). The skip is durable;
  /// the app won't re-prompt for the same pair afterwards.
  Future<void> skipCoRiderRating({
    required String tripId,
    required String coRiderUserId,
  });
}

/// Razorpay order details returned by `POST /unlocks/order`. Same shape
/// as the driver-subscription order but kept separate to avoid coupling
/// the two surfaces.
class UnlockOrder {
  final String orderId;
  final int amountPaise;
  final String currency;
  final String razorpayKeyId;

  const UnlockOrder({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.razorpayKeyId,
  });

  /// Empty keyId means the backend is in stub mode (no Razorpay creds).
  /// Callers should skip the checkout sheet and confirm directly.
  bool get isStub => razorpayKeyId.isEmpty;

  factory UnlockOrder.fromJson(Map<String, dynamic> json) => UnlockOrder(
        orderId: (json['orderId'] as String?) ?? '',
        amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
        currency: (json['currency'] as String?) ?? 'INR',
        razorpayKeyId: (json['razorpayKeyId'] as String?) ?? '',
      );
}
