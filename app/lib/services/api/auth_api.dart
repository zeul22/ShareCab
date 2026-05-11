import '../../models/auth_session.dart';

/// Abstract auth backend. The Mock impl powers local demos; `Msg91AuthApi`
/// handles production phone login with the MSG91 widget SDK.
abstract class AuthApi {
  /// Ask the configured auth backend to send an OTP to [phone]. Returns a
  /// [debugOtp] in mock / dev mode so devs can log in without SMS. In
  /// production this is always null and the OTP arrives via SMS.
  Future<String?> requestOtp(String phone);

  /// Exchange a verified OTP proof for a fresh [AuthSession].
  /// First-time phones auto-create a user account.
  Future<AuthSession> verifyOtp({required String phone, required String otp});

  /// Mint a new access token (and a rotated refresh token) using the current
  /// refresh token. Throws if the refresh token is invalid or revoked.
  Future<AuthSession> refresh(String refreshToken);

  /// Server-side revocation of the refresh token so a logged-out device can't
  /// silently keep refreshing. The client should then drop its local copy.
  Future<void> logout(String refreshToken);
}
