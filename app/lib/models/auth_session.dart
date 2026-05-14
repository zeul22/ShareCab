import 'user.dart';

/// Tokens + user, persisted as a single blob in SharedPreferences.
///
/// **Forever-logged-in design:**
/// The user never sees an expiry. Internally we use two tokens:
///
///   - `accessToken`  — short-lived (15 min in production); proves identity to the API.
///   - `refreshToken` — long-lived; used to mint a fresh access token. Rotates on
///                      every refresh so a stolen refresh token only works until the
///                      legitimate device next refreshes (theft becomes detectable).
///
/// On every refresh, the server issues a *new* refresh token. The user keeps
/// "logging in forever" as long as their device makes at least one call within
/// the refresh window (months). On logout, both tokens are revoked.
class AuthSession {
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final AppUser user;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.user,
  });

  bool get isAccessExpired =>
      DateTime.now().isAfter(accessExpiresAt.subtract(const Duration(seconds: 30)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessExpiresAt': accessExpiresAt.toIso8601String(),
        'user': {
          'id': user.id,
          'name': user.name,
          'phone': user.phone,
          'email': user.email,
          'role': user.role,
          'rating': user.rating,
          'totalRides': user.totalRides,
          'profileCompleted': user.profileCompleted,
        },
      };

  AuthSession copyWith({AppUser? user}) => AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessExpiresAt: accessExpiresAt,
        user: user ?? this.user,
      );

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String),
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
