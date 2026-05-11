import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/auth_session.dart';
import '../../models/user.dart';
import '../../utils/api_config.dart';
import 'auth_api.dart';

/// Dev-fallback HTTP implementation of [AuthApi] that talks to the ShareCab
/// backend at `${ApiConfig.apiRoot}/auth/*`.
///
/// Endpoints (see backend/src/routes/auth.routes.js):
///   POST /api/auth/otp/request   — body {phone}             → {debugOtp}
///   POST /api/auth/otp/verify    — body {phone, otp}        → AuthSession
///   POST /api/auth/refresh       — body {refreshToken}      → AuthSession
///   POST /api/auth/logout        — body {refreshToken}      → 204
///
/// In production, phone login uses [Msg91AuthApi]. These endpoints are kept
/// for local development with `MSG91_DEV_FALLBACK=true`.
class HttpAuthApi implements AuthApi {
  final http.Client _client;
  final String _root;

  HttpAuthApi({http.Client? client, String? apiRoot})
      : _client = client ?? http.Client(),
        _root = apiRoot ?? ApiConfig.apiRoot;

  @override
  Future<String?> requestOtp(String phone) async {
    final res = await _post('/auth/otp/request', {'phone': phone});
    final body = _decode(res);
    return body['debugOtp'] as String?;
  }

  @override
  Future<AuthSession> verifyOtp(
      {required String phone, required String otp}) async {
    final res = await _post('/auth/otp/verify', {'phone': phone, 'otp': otp});
    return _sessionFromJson(_decode(res));
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    final res = await _post('/auth/refresh', {'refreshToken': refreshToken});
    return _sessionFromJson(_decode(res));
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _post('/auth/logout', {'refreshToken': refreshToken},
        expect204: true);
  }

  // ---------------------------------------------------------------------------

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    bool expect204 = false,
  }) async {
    final res = await _client.post(
      Uri.parse('$_root$path'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (expect204 && res.statusCode == 204) return res;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _AuthException.fromResponse(res);
    }
    return res;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  AuthSession _sessionFromJson(Map<String, dynamic> body) {
    return AuthSession(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      accessExpiresAt: DateTime.parse(body['accessExpiresAt'] as String),
      user: AppUser.fromJson(body['user'] as Map<String, dynamic>),
    );
  }
}

class _AuthException implements Exception {
  final int statusCode;
  final String message;

  const _AuthException(this.statusCode, this.message);

  factory _AuthException.fromResponse(http.Response res) {
    String message = 'Auth API ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final m = body['error'] as String?;
      if (m != null) message = m;
    } catch (_) {/* keep default */}
    return _AuthException(res.statusCode, message);
  }

  @override
  String toString() => message;
}
