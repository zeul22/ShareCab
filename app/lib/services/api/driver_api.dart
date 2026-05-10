import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/driver_dispatch.dart';
import '../../models/driver_profile.dart';
import '../../utils/api_config.dart';

typedef AsyncTokenGetter = Future<String?> Function();

/// Driver-side HTTP wrapper. Mirrors the shape of HttpRideApi but for the
/// `/api/drivers/*` surface. Used by [DriverHomeScreen] (and later, the
/// SubscriptionScreen + DriverActiveTripScreen).
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

  Future<DriverProfile> getMyDriver() async {
    final res = await _get('/drivers/me');
    final body = _decode(res);
    final raw = body['driver'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Malformed /drivers/me response');
    }
    return DriverProfile.fromJson(raw);
  }

  /// Toggle online. Backend rejects with 403 if subscription has expired —
  /// the screen surfaces that error so the rider knows to renew.
  Future<DriverProfile> setOnline() async {
    final res = await _post('/drivers/online', const {});
    return _profileFromMutation(_decode(res));
  }

  Future<DriverProfile> setOffline() async {
    final res = await _post('/drivers/offline', const {});
    return _profileFromMutation(_decode(res));
  }

  /// `/online` and `/offline` return the raw Driver doc (without our
  /// composed `subscription` block), so we re-fetch the canonical view.
  /// Avoids hand-merging two different response shapes on the client.
  Future<DriverProfile> _profileFromMutation(Map<String, dynamic> _) {
    return getMyDriver();
  }

  /// Step 1 of renewal: ask the backend to create a Razorpay order. The
  /// returned [SubscriptionOrder] carries everything checkout.js needs
  /// (orderId, amount, key). When `razorpayKeyId` is empty, the backend
  /// is in stub mode — caller should skip checkout and confirm directly.
  Future<SubscriptionOrder> startSubscriptionOrder() async {
    final res = await _post('/drivers/subscribe', const {});
    final body = _decode(res);
    return SubscriptionOrder.fromJson(body);
  }

  /// Step 2 of renewal: post the Razorpay payment receipt back to the
  /// backend so it can verify the HMAC signature and extend the driver's
  /// subscription. Returns the refreshed driver profile so the home
  /// screen can re-render the new expiry without an extra round-trip.
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
    // Confirm returns just the subscription block; re-fetch the full
    // driver doc so DriverHomeScreen has fresh state across all cards.
    return getMyDriver();
  }

  // ---------------------------------------------------------------------------
  // Trip lifecycle (Phase 2.D)
  // ---------------------------------------------------------------------------

  /// Currently dispatched trip(s) for this driver. Returns an empty
  /// [DriverDispatch] (not null) when nothing is assigned — the caller
  /// should branch on `dispatch.isEmpty`. Polled on a tick by the home
  /// screen to surface new dispatches without socket plumbing.
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
  Future<DriverDispatch> markPickedUp(String tripId) =>
      _lifecycleStep('/trips/$tripId/picked-up');

  /// Per-rider dropoff. The driver hits this once they've delivered
  /// this rider; the backend settles their fare and pulls them from
  /// `activeTrips`. The whole group only completes when the LAST sibling
  /// is dropped.
  Future<DriverDispatch> markDropped(String tripId) =>
      _lifecycleStep('/trips/$tripId/dropped');

  Future<DriverDispatch> _lifecycleStep(String path) async {
    final res = await _post(path, const {});
    final body = _decode(res);
    final trips = (body['trips'] as List?) ?? const [];
    return DriverDispatch.fromTrips(trips);
  }

  // ---------------------------------------------------------------------------

  Future<http.Response> _get(String path) async {
    final headers = await _authHeaders();
    final res = await _client.get(Uri.parse('$_root$path'), headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _DriverApiException.fromResponse(res);
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
      throw _DriverApiException.fromResponse(res);
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

class _DriverApiException implements Exception {
  final int statusCode;
  final String message;

  const _DriverApiException(this.statusCode, this.message);

  factory _DriverApiException.fromResponse(http.Response res) {
    String message = 'Driver API ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final m = body['error'] as String?;
      if (m != null) message = m;
    } catch (_) {/* keep default */}
    return _DriverApiException(res.statusCode, message);
  }

  @override
  String toString() => message;
}
