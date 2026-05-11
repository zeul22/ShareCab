import '../../models/auth_session.dart';

/// Abstract auth backend. `HttpAuthApi` handles the dev-OTP / refresh /
/// logout paths; `Msg91AuthApi` wraps the production MSG91 widget SDK.
abstract class AuthApi {
  /// Ask the backend (or MSG91, if enabled) to send an OTP to [phone].
  /// Returns a `debugOtp` in dev mode so devs can log in without SMS.
  /// Production always returns null — the OTP arrives via SMS.
  Future<String?> requestOtp(String phone);

  /// Exchange a verified OTP proof for a fresh [AuthSession]. First-time
  /// phones auto-create a user account on the backend (role=rider; the
  /// driver app then promotes the account through /drivers/onboard).
  Future<AuthSession> verifyOtp({required String phone, required String otp});

  Future<AuthSession> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
}
