import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/driver_dispatch.dart';
import '../../models/driver_profile.dart';
import '../../models/trip_offer.dart';
import '../../utils/api_config.dart';

typedef AsyncTokenGetter = Future<String?> Function();

/// Submission payload for `POST /api/drivers/onboard`. The backend
/// promotes the requesting user to `role=driver` and creates the Driver
/// document with `verificationStatus='pending'`.
class OnboardingSubmission {
  final String fullName;
  final String? email;
  final String licenseNumber;
  final String vehicleModel;
  final String plate;
  final String? color;
  final int capacity;

  const OnboardingSubmission({
    required this.fullName,
    this.email,
    required this.licenseNumber,
    required this.vehicleModel,
    required this.plate,
    this.color,
    this.capacity = 4,
  });

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        if (email != null && email!.isNotEmpty) 'email': email,
        'licenseNumber': licenseNumber,
        'vehicle': {
          'model': vehicleModel,
          'plate': plate,
          if (color != null && color!.isNotEmpty) 'color': color,
          'capacity': capacity,
        },
      };
}

/// Thin HTTP wrapper over `/api/drivers/*`. Used by:
///   - SplashScreen + OtpVerifyScreen: `getMyDriverOrNull` to route
///     to onboarding (no doc) / pending-review (status=pending) / home
///     (status=approved).
///   - OnboardingScreen: `submitOnboarding` to create the Driver doc.
///   - HomeScreen: `getMyDriver`, `setOnline`/`setOffline`, dispatch
///     polling, subscription renewal.
///   - ActiveTripScreen: `getMyDispatch` polling + the three trip-
///     lifecycle endpoints.
///   - LocationPushService: `updateLocation` ticking while online.
class DriverApi {
  final http.Client _client;
  final String _root;
  final AsyncTokenGetter _tokenGetter;

  DriverApi({
    required AsyncTokenGetter tokenGetter,
    http.Client? client,
    String? apiRoot,
  })  : _client = client ?? http.Client(),
        _root = apiRoot ?? ApiConfig.apiRoot,
        _tokenGetter = tokenGetter;

  // ---------------------------------------------------------------------------
  // Profile + onboarding
  // ---------------------------------------------------------------------------

  /// Returns the driver profile, or null when the user has no Driver
  /// record yet (HTTP 404). Any other failure rethrows.
  Future<DriverProfile?> getMyDriverOrNull() async {
    try {
      final res = await _get('/drivers/me');
      final body = _decode(res);
      final raw = body['driver'];
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Malformed /drivers/me response');
      }
      return DriverProfile.fromJson(raw);
    } on DriverApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Throwing variant — for code paths past onboarding where a Driver
  /// doc is guaranteed to exist (HomeScreen, ActiveTripScreen). 404 here
  /// is a bug, not a soft fail.
  Future<DriverProfile> getMyDriver() async {
    final p = await getMyDriverOrNull();
    if (p == null) {
      throw const DriverApiException(404, 'Driver profile not found');
    }
    return p;
  }

  Future<DriverProfile> submitOnboarding(OnboardingSubmission submission) async {
    final res = await _post('/drivers/onboard', submission.toJson());
    final body = _decode(res);
    final raw = body['driver'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Malformed /drivers/onboard response');
    }
    return DriverProfile.fromJson(raw);
  }

  // ---------------------------------------------------------------------------
  // Online toggle + location push
  // ---------------------------------------------------------------------------

  Future<DriverProfile> setOnline() async {
    await _post('/drivers/online', const {});
    return getMyDriver();
  }

  Future<DriverProfile> setOffline() async {
    await _post('/drivers/offline', const {});
    return getMyDriver();
  }

  /// LocationPushService ticks this every 20 seconds while the driver is
  /// online so the rider app's "your driver is X minutes away" view + the
  /// matching engine's 2dsphere query both have fresh coordinates.
  Future<void> updateLocation({required double lat, required double lng}) async {
    await _post('/drivers/location', {'lat': lat, 'lng': lng});
  }

  // ---------------------------------------------------------------------------
  // Driver offer flow (Uber-style accept/reject)
  // ---------------------------------------------------------------------------

  /// Current pending offer for this driver, or null when nothing is on
  /// the wire. Polled at 3s cadence from the home screen while online
  /// + unassigned. 204 from the backend → null here.
  Future<TripOffer?> getMyOffer() async {
    final res = await _get('/drivers/me/offer');
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    final body = _decode(res);
    final raw = body['offer'];
    if (raw is! Map<String, dynamic>) return null;
    return TripOffer.fromTripJson(raw);
  }

  /// Accept the offered trip. Backend transitions status → driver_assigned
  /// and populates Driver.activeTrips, which the next /drivers/me poll
  /// surfaces — and from there the home screen auto-pushes to ActiveTripScreen.
  Future<void> acceptOffer(String tripId) async {
    await _post('/drivers/offers/$tripId/accept', const {});
  }

  /// Reject the offered trip. Backend pushes this driver into
  /// `Trip.rejectedBy` and re-dispatches to the next-nearest driver.
  Future<void> rejectOffer(String tripId) async {
    await _post('/drivers/offers/$tripId/reject', const {});
  }

  // ---------------------------------------------------------------------------
  // Dispatch + trip lifecycle
  // ---------------------------------------------------------------------------

  /// Currently dispatched trip(s) for this driver. Returns an empty
  /// [DriverDispatch] (not null) when nothing is assigned — the caller
  /// should branch on `dispatch.isEmpty`. Polled on a tick by the home
  /// screen + active trip screen.
  Future<DriverDispatch> getMyDispatch() async {
    final res = await _get('/drivers/me/dispatch');
    final body = _decode(res);
    final trips = (body['trips'] as List?) ?? const [];
    return DriverDispatch.fromTrips(trips);
  }

  /// Backend's arrive/start/complete handlers walk the whole sibling
  /// matchGroup atomically — passing any trip id from the dispatch
  /// advances all riders together, so the screen always uses
  /// `dispatch.primaryTripId`.
  Future<DriverDispatch> arriveTrip(String tripId) =>
      _lifecycleStep('/trips/$tripId/arrive');

  /// Per-rider pickup. Pass the *specific* trip id whose rider just
  /// boarded — siblings stay in their current state (e.g. still
  /// `arriving` if not yet picked up).
  ///
  /// Backend requires [otp] — the 4-digit code shown on the rider's
  /// confirmation screen. Wrong OTP returns 400; the driver-side modal
  /// surfaces this so they can ask the rider to re-check.
  ///
  /// Optionally include the driver's current GPS so the backend can
  /// persist `actualPickup` on the trip. The rider's map snaps the
  /// source pin to this location once the trip flips to in_progress.
  Future<DriverDispatch> markPickedUp(
    String tripId, {
    required String otp,
    double? lat,
    double? lng,
  }) =>
      _lifecycleStep('/trips/$tripId/picked-up', lat: lat, lng: lng, otp: otp);

  /// Per-rider dropoff. The driver hits this once they've delivered
  /// this rider; the backend settles their fare and pulls them from
  /// `activeTrips`. The whole group only completes when the LAST sibling
  /// is dropped. Optional GPS lands on `actualDropoff` for audit.
  Future<DriverDispatch> markDropped(
    String tripId, {
    double? lat,
    double? lng,
  }) =>
      _lifecycleStep('/trips/$tripId/dropped', lat: lat, lng: lng);

  Future<DriverDispatch> _lifecycleStep(
    String path, {
    double? lat,
    double? lng,
    String? otp,
  }) async {
    final body = <String, dynamic>{
      if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
      if (otp != null && otp.isNotEmpty) 'otp': otp,
    };
    final res = await _post(path, body);
    final decoded = _decode(res);
    final trips = (decoded['trips'] as List?) ?? const [];
    return DriverDispatch.fromTrips(trips);
  }

  // ---------------------------------------------------------------------------
  // Subscription renewal
  // ---------------------------------------------------------------------------

  /// Step 1 of renewal: ask the backend to create a Razorpay order. When
  /// `razorpayKeyId` is empty, the backend is in stub mode — caller should
  /// skip checkout and confirm directly.
  Future<SubscriptionOrder> startSubscriptionOrder() async {
    final res = await _post('/drivers/subscribe', const {});
    final body = _decode(res);
    return SubscriptionOrder.fromJson(body);
  }

  /// Step 2 of renewal: post the Razorpay payment receipt back so the
  /// backend can verify the HMAC and extend the driver's subscription.
  /// Returns the refreshed driver profile so the home screen can re-render
  /// the new expiry without an extra round-trip.
  Future<DriverProfile> confirmSubscription({
    required String orderId,
    required String paymentRef,
    required int amountPaise,
    String? signature,
  }) async {
    await _post('/drivers/subscribe/confirm', {
      'orderId': orderId,
      'paymentRef': paymentRef,
      'amountPaise': amountPaise,
      if (signature != null) 'signature': signature,
    });
    return getMyDriver();
  }

  // ---------------------------------------------------------------------------

  Future<http.Response> _get(String path) async {
    final headers = await _authHeaders();
    final res = await _client.get(Uri.parse('$_root$path'), headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DriverApiException.fromResponse(res);
    }
    return res;
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final headers = await _authHeaders();
    final res = await _client.post(
      Uri.parse('$_root$path'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DriverApiException.fromResponse(res);
    }
    return res;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenGetter();
    if (token == null) {
      throw Exception('Not signed in');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

class DriverApiException implements Exception {
  final int statusCode;
  final String message;

  const DriverApiException(this.statusCode, this.message);

  factory DriverApiException.fromResponse(http.Response res) {
    String message = 'Driver API ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final m = body['error'] as String?;
      if (m != null) message = m;
    } catch (_) {/* keep default */}
    return DriverApiException(res.statusCode, message);
  }

  @override
  String toString() => message;
}
