import '../../models/auth_session.dart';
import '../../utils/api_config.dart';
import 'auth_api.dart';
import 'http_auth_api.dart';
import 'msg91_auth_api.dart';

/// [AuthApi] facade that picks the right underlying api at call time.
///
/// The previous wiring snapshot-checked `ApiConfig.msg91Enabled` once at
/// app boot and locked in [HttpAuthApi] vs [Msg91AuthApi]. That broke any
/// situation where the backend's `/auth/otp/msg91/config` wasn't reachable
/// at startup (backend not up yet, slow first-fetch) — the app stayed on
/// the HTTP/dev-OTP path even after the runtime config later loaded
/// successfully, and the rider saw the 503 "Configure MSG91…" error.
///
/// This proxy re-evaluates per call:
///   1. Best-effort refresh of the runtime widget config (cheap no-op
///      after the first successful fetch).
///   2. Dispatch to [Msg91AuthApi] if MSG91 is now enabled, else
///      [HttpAuthApi] (which surfaces the same 503 when the dev fallback
///      is off — useful so the rider sees the actionable config error
///      instead of a silent hang).
class DynamicAuthApi implements AuthApi {
  final HttpAuthApi _http;
  final Msg91AuthApi _msg91;

  DynamicAuthApi({HttpAuthApi? http, Msg91AuthApi? msg91})
      : _http = http ?? HttpAuthApi(),
        _msg91 = msg91 ?? Msg91AuthApi();

  AuthApi get _current => ApiConfig.msg91Enabled ? _msg91 : _http;

  @override
  Future<String?> requestOtp(String phone) async {
    await ApiConfig.loadRuntimeMsg91Config();
    return _current.requestOtp(phone);
  }

  @override
  Future<AuthSession> verifyOtp(
      {required String phone, required String otp}) async {
    await ApiConfig.loadRuntimeMsg91Config();
    return _current.verifyOtp(phone: phone, otp: otp);
  }

  // Refresh + logout don't depend on the OTP path — always go through
  // the HTTP backend, which is the same path Msg91AuthApi delegates to
  // anyway.
  @override
  Future<AuthSession> refresh(String refreshToken) =>
      _http.refresh(refreshToken);

  @override
  Future<void> logout(String refreshToken) => _http.logout(refreshToken);
}
