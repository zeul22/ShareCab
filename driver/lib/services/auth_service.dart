import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';
import '../models/user.dart';
import 'api/auth_api.dart';

/// Phone + OTP auth with persistent sessions. Identical surface to the
/// rider app's AuthService so the OTP screen ports verbatim.
class AuthService extends ChangeNotifier {
  final AuthApi _api;
  AuthService(this._api);

  // Bumped storage namespace for the driver app so a previously-installed
  // ShareCab rider session on the same device can't accidentally hydrate
  // here (shared_preferences scopes by app, but the explicit key keeps
  // the intent obvious).
  static const _storageKey = 'sharecab.driver.auth.session.v1';

  AuthSession? _session;
  String? _pendingPhone;
  Future<AuthSession>? _refreshInFlight;

  AuthSession? get session => _session;
  AppUser? get user => _session?.user;
  String? get pendingPhone => _pendingPhone;
  bool get isAuthenticated => _session != null;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      notifyListeners();
      return;
    }
    try {
      _session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_storageKey);
      _session = null;
      notifyListeners();
      return;
    }

    if (_session!.isAccessExpired) {
      try {
        await _refreshSession();
      } catch (_) {
        await _clear();
      }
    }
    notifyListeners();
  }

  Future<String?> requestOtp(String phone) async {
    final cleaned = _normalizePhone(phone);
    final debugOtp = await _api.requestOtp(cleaned);
    _pendingPhone = cleaned;
    notifyListeners();
    return debugOtp;
  }

  Future<void> verifyOtp(String otp) async {
    final phone = _pendingPhone;
    if (phone == null) {
      throw StateError('Request an OTP before verifying');
    }
    final session = await _api.verifyOtp(phone: phone, otp: otp);
    await _persist(session);
    _pendingPhone = null;
    notifyListeners();
  }

  void cancelOtp() {
    _pendingPhone = null;
    notifyListeners();
  }

  Future<String?> accessTokenForApi() async {
    final s = _session;
    if (s == null) return null;
    if (s.isAccessExpired) {
      try {
        final fresh = await _refreshSession();
        return fresh.accessToken;
      } catch (_) {
        await _clear();
        return null;
      }
    }
    return s.accessToken;
  }

  /// Force-mint a fresh session via the refresh endpoint. The new JWT
  /// is built from the *current* User document on the server, so this
  /// is how we pick up a role change (rider → driver after onboarding)
  /// without making the user log out and back in. Returns false when
  /// the refresh fails — the caller should treat that as logged-out.
  Future<bool> forceRefresh() async {
    if (_session == null) return false;
    try {
      await _refreshSession();
      return true;
    } catch (_) {
      await _clear();
      return false;
    }
  }

  Future<void> logout() async {
    final s = _session;
    if (s != null) {
      try {
        await _api.logout(s.refreshToken);
      } catch (_) {/* server unreachable shouldn't block local logout */}
    }
    await _clear();
  }

  Future<AuthSession> _refreshSession() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final s = _session;
    if (s == null) {
      return Future.error(StateError('No session to refresh'));
    }

    final future = _api.refresh(s.refreshToken).then((next) async {
      await _persist(next);
      return next;
    }).whenComplete(() => _refreshInFlight = null);

    _refreshInFlight = future;
    return future;
  }

  Future<void> _persist(AuthSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(session.toJson()));
    notifyListeners();
  }

  Future<void> _clear() async {
    _session = null;
    _pendingPhone = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  String _normalizePhone(String input) {
    final trimmed = input.trim();
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return hasPlus ? '+$digits' : digits;
  }
}
