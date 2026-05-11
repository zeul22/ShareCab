import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

import '../../models/auth_session.dart';
import '../../models/user.dart';
import '../../utils/api_config.dart';
import 'auth_api.dart';
import 'http_auth_api.dart';

/// MSG91-backed [AuthApi]. OTP send + verify run on the device via
/// MSG91's widget SDK; once the SDK returns a JWT-style access token,
/// we exchange it at our backend's `/auth/otp/msg91/verify`. Refresh
/// + logout are still our backend's concern (delegated to HttpAuthApi).
class Msg91AuthApi implements AuthApi {
  final HttpAuthApi _backend;
  final http.Client _client;
  final String _root;
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
    final identifier = phone.startsWith('+') ? phone.substring(1) : phone;
    Map<String, dynamic>? res;
    try {
      res = await OTPWidget.sendOTP({'identifier': identifier});
    } catch (e) {
      debugPrint('[msg91] sendOTP threw: $e');
      throw Exception('MSG91 sendOTP failed: $e');
    }
    debugPrint('[msg91] sendOTP raw response: $res');

    final reqId = _extractReqId(res);
    if (reqId == null) {
      throw Exception(_extractMessage(
        res,
        'MSG91 didn\'t return a reqId. Raw response: ${jsonEncode(res ?? {})}',
      ));
    }
    _lastReqId = reqId;
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
      throw Exception(
        'MSG91 verified the OTP but returned no access token. Check that '
        '"Mobile Integration" is enabled on the widget. '
        'Raw response: ${jsonEncode(res ?? {})}',
      );
    }
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

  bool _looksLikeReqId(String s) =>
      RegExp(r'^[A-Za-z0-9_-]{12,}$').hasMatch(s);

  bool _isVerifySuccess(Map<String, dynamic>? res) {
    if (res == null) return false;
    final type = res['type'];
    if (type is String && type.toLowerCase() == 'success') return true;
    return false;
  }

  String? _extractAccessToken(Map<String, dynamic>? res) {
    if (res == null) return null;
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
