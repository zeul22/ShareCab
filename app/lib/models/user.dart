class AppUser {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final double rating;
  final int totalRides;

  /// Derived backend-side: true once the rider has supplied a real name
  /// + email via OnboardingScreen. False for a brand-new rider auto-
  /// created from an OTP verify (their `name` is the placeholder
  /// 'Rider' and they have no email yet). Drivers are always true —
  /// their onboarding lives in a separate flow.
  ///
  /// Old backends that don't surface this field default to true so we
  /// don't bounce existing users through onboarding on rollout.
  final bool profileCompleted;

  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    required this.rating,
    required this.totalRides,
    this.profileCompleted = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id']?.toString() ?? '',
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        email: json['email'],
        role: json['role'] ?? 'rider',
        rating: (json['rating'] ?? 5).toDouble(),
        totalRides: json['totalRides'] ?? 0,
        profileCompleted: json['profileCompleted'] as bool? ?? true,
      );

  AppUser copyWith({
    String? name,
    String? email,
    bool? profileCompleted,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        phone: phone,
        email: email ?? this.email,
        role: role,
        rating: rating,
        totalRides: totalRides,
        profileCompleted: profileCompleted ?? this.profileCompleted,
      );
}
