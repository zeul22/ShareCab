import 'user.dart';

/// Tokens + user, persisted as a single blob in SharedPreferences. Same
/// shape as the rider app's session — the backend issues the same response
/// shape for both apps.
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

  bool get isAccessExpired => DateTime.now()
      .isAfter(accessExpiresAt.subtract(const Duration(seconds: 30)));

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
        },
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String),
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
