import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

import '../../models/auth_session.dart';
import '../../models/user.dart';
import '../../utils/api_config.dart';
import 'auth_api.dart';
import 'http_auth_api.dart';

/// MSG91-backed [AuthApi]. Handles the OTP send + verify entirely on
/// the device using the MSG91 widget SDK; once the SDK returns a JWT-
/// style access token, we exchange it at our backend's
/// `/auth/otp/msg91/verify` endpoint, which re-validates with MSG91 and
/// issues our own session.
///
/// Refresh + logout are still our backend's concern — those are
/// delegated to an inner [HttpAuthApi].
class Msg91AuthApi implements AuthApi {
  final HttpAuthApi _backend;
  final http.Client _client;
  final String _root;

  /// Last reqId returned from MSG91's sendOTP. We need it on the verify
  /// call so the SDK can match the OTP to the right request — the
  /// rider-side flow always pairs one send with one verify, so a single
  /// instance field is enough.
  String? _lastReqId;

  Msg91AuthApi({
    HttpAuthApi? backend,
    http.Client? client,
    String? apiRoot,
  })  : _backend = backend ?? HttpAuthApi(),
        _client = client ?? http.Client(),
        _root = apiRoot ?? ApiConfig.apiRoot;

  @override
  Future<String?> requestOtp(String phone) async {
    // MSG91 expects the identifier to be the country-code-prefixed phone
    // WITHOUT a `+`. Our app stores phones in `+91XXXXXXXXXX` form, so
    // strip the leading `+`. India-only scope keeps this unambiguous.
    final identifier = phone.startsWith('+') ? phone.substring(1) : phone;

    Map<String, dynamic>? res;
    try {
      res = await OTPWidget.sendOTP({'identifier': identifier});
    } catch (e) {
      // SDK rethrows network / API errors wrapped in a generic Exception.
      // Surface the underlying message so the screen's error banner is
      // actionable instead of "Exception: …".
      debugPrint('[msg91] sendOTP threw: $e');
      throw Exception('MSG91 sendOTP failed: $e');
    }
    debugPrint('[msg91] sendOTP raw response: $res');

    final reqId = _extractReqId(res);
    if (reqId == null) {
      // Include the full body in the error so we can see exactly what
      // MSG91 returned (wrong widgetId, blocked sender id, etc.).
      throw Exception(_extractMessage(
        res,
        'MSG91 didn\'t return a reqId. Raw response: ${jsonEncode(res ?? {})}',
      ));
    }
    _lastReqId = reqId;
    // Production never shares a debug OTP — only the dev path does that.
    return null;
  }

  @override
  Future<AuthSession> verifyOtp(
      {required String phone, required String otp}) async {
    final reqId = _lastReqId;
    if (reqId == null) {
      throw Exception('No OTP request in flight — request a fresh OTP first');
    }
    Map<String, dynamic>? res;
    try {
      res = await OTPWidget.verifyOTP({'reqId': reqId, 'otp': otp});
    } catch (e) {
      debugPrint('[msg91] verifyOTP threw: $e');
      throw Exception('MSG91 verifyOTP failed: $e');
    }
    debugPrint('[msg91] verifyOTP raw response: $res');

    if (!_isVerifySuccess(res)) {
      throw Exception(_extractMessage(res, 'Invalid OTP'));
    }
    final accessToken = _extractAccessToken(res);
    if (accessToken == null || accessToken.isEmpty) {
      // SDK accepted the OTP but didn't return the token we need to
      // exchange with the backend. This usually means the widget config
      // doesn't have "Mobile Integration" enabled in the MSG91 dashboard.
      throw Exception(
        'MSG91 verified the OTP but returned no access token. Check that '
        '"Mobile Integration" is enabled on the widget. '
        'Raw response: ${jsonEncode(res ?? {})}',
      );
    }
    // Token shape preview + JWT-shape sanity check. A real MSG91 JWT
    // is 100+ chars in three dot-separated parts. Anything dramatically
    // shorter, or missing dots, means `_extractAccessToken` picked up
    // the wrong field — a "msg91 code 418" rejection from the backend
    // is the same root cause in that case.
    if (kDebugMode) {
      final preview = accessToken.length > 16
          ? '${accessToken.substring(0, 8)}…${accessToken.substring(accessToken.length - 4)} (len=${accessToken.length})'
          : accessToken;
      final looksLikeJwt = accessToken.split('.').length == 3 &&
          accessToken.length >= 100;
      debugPrint(
        '═══════════ [msg91] verifyOTP DIAGNOSTIC ═══════════\n'
        'extracted accessToken preview: $preview\n'
        'looks like a JWT? $looksLikeJwt\n'
        'raw SDK response: ${jsonEncode(res ?? {})}\n'
        '════════════════════════════════════════════════════',
      );
    }
    // Backend re-validates the token via MSG91's verifyAccessToken and
    // issues our own session. Use the original `+91…` form for the
    // phone so the User document in Mongo stays consistent with the
    // dev-OTP path.
    final session =
        await _exchangeAtBackend(phone: phone, accessToken: accessToken);
    _lastReqId = null;
    return session;
  }

  @override
  Future<AuthSession> refresh(String refreshToken) =>
      _backend.refresh(refreshToken);

  @override
  Future<void> logout(String refreshToken) => _backend.logout(refreshToken);

  // ---------------------------------------------------------------------------

  Future<AuthSession> _exchangeAtBackend({
    required String phone,
    required String accessToken,
  }) async {
    final res = await _client.post(
      Uri.parse('$_root/auth/otp/msg91/verify'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'accessToken': accessToken}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Auth exchange failed (${res.statusCode})';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final m = body['error'] as String?;
        if (m != null) msg = m;
      } catch (_) {/* keep default */}
      throw Exception(msg);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return AuthSession(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      accessExpiresAt: DateTime.parse(body['accessExpiresAt'] as String),
      user: AppUser.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  /// MSG91 wraps responses inconsistently across endpoints. The reqId
  /// can show up under `data.reqId`, `message.reqId`, or as the raw
  /// `message` string itself. Probe each path; bail out cleanly if
  /// none match (caller throws with the SDK's error message).
  String? _extractReqId(Map<String, dynamic>? res) {
    if (res == null) return null;
    final data = res['data'];
    if (data is Map && data['reqId'] is String) return data['reqId'] as String;
    if (res['reqId'] is String) return res['reqId'] as String;
    if (res['request_id'] is String) return res['request_id'] as String;
    final message = res['message'];
    if (message is Map && message['reqId'] is String) {
      return message['reqId'] as String;
    }
    if (message is String && message.length > 8 && _looksLikeReqId(message)) {
      return message;
    }
    return null;
  }

  bool _looksLikeReqId(String s) {
    // ReqIds are hex-ish strings; rules out human-readable error text.
    return RegExp(r'^[A-Za-z0-9_-]{12,}$').hasMatch(s);
  }

  bool _isVerifySuccess(Map<String, dynamic>? res) {
    if (res == null) return false;
    final type = res['type'];
    if (type is String && type.toLowerCase() == 'success') return true;
    return false;
  }

  String? _extractAccessToken(Map<String, dynamic>? res) {
    if (res == null) return null;
    // MSG91's verify response may carry the JWT as `access-token`,
    // `message`, or inside `data`, depending on widget version.
    final directToken =
        res['access-token'] ?? res['access_token'] ?? res['accessToken'];
    if (directToken is String && directToken.isNotEmpty) return directToken;
    final direct = res['message'];
    if (direct is String && direct.isNotEmpty) return direct;
    final data = res['data'];
    if (data is Map) {
      final m = data['message'];
      if (m is String && m.isNotEmpty) return m;
      final t =
          data['access-token'] ?? data['access_token'] ?? data['accessToken'];
      if (t is String && t.isNotEmpty) return t;
    }
    return null;
  }

  String _extractMessage(Map<String, dynamic>? res, String fallback) {
    final m = res?['message'];
    if (m is String && m.isNotEmpty) return m;
    final data = res?['data'];
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return fallback;
  }
}
