import 'dart:convert';
import 'dart:math';

import '../../models/auth_session.dart';
import '../../models/user.dart';
import 'auth_api.dart';

/// In-memory mock of [AuthApi] for the scaffold.
///
/// Demo credentials (visible on the login screen):
///   Phone: [demoPhone] = "9999900001"
///   OTP:   [demoOtp]   = "123456"
///
/// In mock mode, **any phone with the right format will accept "123456" as
/// the OTP** so reviewers can try multiple accounts. A user record is created
/// on the fly the first time a phone is verified.
class MockAuthApi implements AuthApi {
  static const String demoPhone = '9999900001';
  static const String demoOtp = '123456';

  /// Production access tokens are short-lived; in the mock we keep that
  /// behavior (15 min) so the auto-refresh path actually exercises.
  static const Duration accessLifetime = Duration(minutes: 15);

  final Random _rng = Random();

  // Keyed by phone — a tiny in-memory user store + revocation set.
  final Map<String, AppUser> _users = {};
  final Set<String> _revokedRefreshTokens = {};

  Duration _latency() => Duration(milliseconds: 250 + _rng.nextInt(350));

  @override
  Future<String?> requestOtp(String phone) async {
    await Future.delayed(_latency());
    if (!_isPhoneValid(phone)) {
      throw ArgumentError('Enter a valid phone number');
    }
    // Echo the demo OTP back so the UI can prefill / hint it.
    return demoOtp;
  }

  @override
  Future<AuthSession> verifyOtp({required String phone, required String otp}) async {
    await Future.delayed(_latency());
    if (!_isPhoneValid(phone)) {
      throw ArgumentError('Enter a valid phone number');
    }
    if (otp != demoOtp) {
      throw ArgumentError('Wrong OTP. Try $demoOtp.');
    }

    final user = _users.putIfAbsent(phone, () => _seedUserForPhone(phone));
    return _issueSession(user);
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    await Future.delayed(_latency());
    if (_revokedRefreshTokens.contains(refreshToken)) {
      throw StateError('Refresh token revoked');
    }
    final phone = _phoneFromRefreshToken(refreshToken);
    if (phone == null) {
      throw StateError('Invalid refresh token');
    }
    final user = _users[phone];
    if (user == null) {
      throw StateError('User no longer exists');
    }
    // Rotate: revoke the old refresh token and issue a new pair.
    _revokedRefreshTokens.add(refreshToken);
    return _issueSession(user);
  }

  @override
  Future<void> logout(String refreshToken) async {
    await Future.delayed(_latency());
    _revokedRefreshTokens.add(refreshToken);
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  bool _isPhoneValid(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 && digits.length <= 15;
  }

  AppUser _seedUserForPhone(String phone) {
    final isDemo = phone == demoPhone;
    return AppUser(
      id: 'usr_${phone.hashCode.toUnsigned(32).toRadixString(16)}',
      name: isDemo ? 'Aditya' : 'Rider',
      phone: phone,
      email: null,
      role: 'rider',
      rating: 5.0,
      totalRides: 0,
    );
  }

  AuthSession _issueSession(AppUser user) {
    final now = DateTime.now();
    final access = _opaqueToken('a', user.phone, now.millisecondsSinceEpoch);
    final refresh = _opaqueToken('r', user.phone, now.microsecondsSinceEpoch);
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAt: now.add(accessLifetime),
      user: user,
    );
  }

  /// Opaque token of the form `<prefix>.<base64(phone:nonce)>`. Real backends
  /// would issue a signed JWT for the access token and a randomly-generated
  /// 256-bit secret (hashed server-side) for the refresh token. The shape here
  /// is enough for the mock to recognize its own tokens.
  String _opaqueToken(String prefix, String phone, int nonce) {
    final payload = base64Url.encode(utf8.encode('$phone:$nonce'));
    return '$prefix.$payload';
  }

  String? _phoneFromRefreshToken(String token) {
    if (!token.startsWith('r.')) return null;
    try {
      final raw = utf8.decode(base64Url.decode(token.substring(2)));
      final colon = raw.indexOf(':');
      return colon < 0 ? null : raw.substring(0, colon);
    } catch (_) {
      return null;
    }
  }
}
