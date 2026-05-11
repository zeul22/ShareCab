class AppUser {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final double rating;
  final int totalRides;

  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    required this.rating,
    required this.totalRides,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id']?.toString() ?? '',
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        email: json['email'],
        role: json['role'] ?? 'rider',
        rating: (json['rating'] ?? 5).toDouble(),
        totalRides: json['totalRides'] ?? 0,
      );
}
