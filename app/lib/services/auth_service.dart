import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';
import '../models/user.dart';
import 'api/auth_api.dart';

/// Phone + OTP auth with persistent "forever-logged-in" sessions.
///
/// Flow:
///   1. `requestOtp(phone)`  — server sends OTP (or returns it in mock mode).
///   2. `verifyOtp(otp)`     — exchange phone + OTP for an [AuthSession].
///   3. Session is persisted; access token auto-refreshes silently when needed.
///   4. `logout()`           — revokes the refresh token and clears local state.
///
/// The user never sees an expiry: as long as the refresh token is valid, calls
/// to [accessTokenForApi] silently mint a fresh access token in the background.
class AuthService extends ChangeNotifier {
  final AuthApi _api;
  AuthService(this._api);

  static const _storageKey = 'sharecab.auth.session.v1';

  AuthSession? _session;
  String? _pendingPhone; // phone awaiting OTP verification
  Future<AuthSession>? _refreshInFlight; // de-dupes concurrent refreshes

  // ---------------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------------

  AuthSession? get session => _session;
  AppUser? get user => _session?.user;
  String? get pendingPhone => _pendingPhone;
  bool get isAuthenticated => _session != null;

  /// Restore a persisted session on app start. If the access token is expired,
  /// silently refresh. If refresh fails, clear local state so the user lands
  /// on the login flow.
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

  /// Trigger an OTP send. In mock / dev mode the API echoes the OTP back so
  /// the UI can prefill or display a hint.
  Future<String?> requestOtp(String phone) async {
    final cleaned = _normalizePhone(phone);
    final debugOtp = await _api.requestOtp(cleaned);
    _pendingPhone = cleaned;
    notifyListeners();
    return debugOtp;
  }

  /// Verify the OTP for the previously-requested phone. On success we persist
  /// the new session and the user is "logged in forever".
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

  /// Clear pending phone (e.g. user tapped back from the OTP screen).
  void cancelOtp() {
    _pendingPhone = null;
    notifyListeners();
  }

  /// Returns a usable access token, refreshing first if it's expired. Network
  /// callers should grab the token via this method, not via `session.accessToken`,
  /// so they always get a fresh one.
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

  /// Force a refresh — useful after a 401 to recover and retry.
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

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<AuthSession> _refreshSession() {
    // De-dupe: many concurrent API calls may notice expiry simultaneously.
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
    // Keep only digits + a leading + so the user can type "+91 99999 00001".
    final trimmed = input.trim();
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return hasPlus ? '+$digits' : digits;
  }
}
