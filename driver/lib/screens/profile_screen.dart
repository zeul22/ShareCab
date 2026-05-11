import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/driver_profile.dart';
import '../models/vehicle.dart';
import '../routes.dart';
import '../services/api/driver_api.dart';
import '../services/auth_service.dart';
import '../services/location_push_service.dart';
import '../theme/app_theme.dart';

/// Profile + settings. Read-only view of identity, vehicle, subscription,
/// and licence (masked). Sign-out is the only mutation — edit-vehicle and
/// edit-bank flows are follow-ups.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DriverProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await context.read<DriverApi>().getMyDriverOrNull();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  Future<void> _signOut() async {
    // Stop location pings before clearing the session so any in-flight tick
    // sees a still-valid token. Otherwise the request fails noisily after
    // logout for no benefit.
    context.read<LocationPushService>().stop();
    final auth = context.read<AuthService>();
    await auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(Routes.phoneEntry, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.brand,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _IdentityCard(
                name: user?.name ?? '—',
                phone: user?.phone ?? '',
                role: user?.role ?? 'driver',
                rating: user?.rating ?? 5.0,
              ),
              const SizedBox(height: 16),
              if (_loading && _profile == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorRow(message: _error!)
              else if (_profile != null) ...[
                _VehicleCard(vehicle: _profile!.vehicle),
                const SizedBox(height: 16),
                _SubscriptionRow(profile: _profile!),
                const SizedBox(height: 16),
                _LicenseRow(licenseNumber: _profile!.licenseNumber),
                const SizedBox(height: 16),
                _StatusRow(verificationStatus: _profile!.verificationStatus),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, color: AppTheme.warn),
                label: const Text(
                  'Sign out',
                  style: TextStyle(
                      color: AppTheme.warn, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.warn),
                ),
              ),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'ShareCab Driver · v0.1.0',
                  style: TextStyle(color: Colors.black38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _IdentityCard extends StatelessWidget {
  final String name;
  final String phone;
  final String role;
  final double rating;
  const _IdentityCard({
    required this.name,
    required this.phone,
    required this.role,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initialsOf(name);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.brand,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style:
                      const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.brand,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: Colors.amber, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E7EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_car_outlined,
                  color: AppTheme.brand, size: 20),
              SizedBox(width: 8),
              Text(
                'VEHICLE',
                style: TextStyle(
                  color: AppTheme.brandDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            vehicle.model.isEmpty ? 'Vehicle' : vehicle.model,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [
              vehicle.plate,
              if (vehicle.color.isNotEmpty) vehicle.color,
              vehicle.type.label,
            ].where((s) => s.isNotEmpty).join(' · '),
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  final DriverProfile profile;
  const _SubscriptionRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final sub = profile.subscription;
    final active = sub.isSubscribed;
    final daysLeft = sub.daysLeft;
    return _InfoRow(
      icon: active ? Icons.workspace_premium : Icons.lock_outline,
      iconColor: active ? AppTheme.brand : AppTheme.warn,
      title: active ? 'Subscription active' : 'Subscription expired',
      subtitle: active
          ? '${daysLeft ?? 0} day${daysLeft == 1 ? '' : 's'} left'
          : 'Renew from the home screen to go online again.',
    );
  }
}

class _LicenseRow extends StatelessWidget {
  final String licenseNumber;
  const _LicenseRow({required this.licenseNumber});

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      icon: Icons.badge_outlined,
      iconColor: AppTheme.brandDark,
      title: 'Driving licence',
      subtitle: _mask(licenseNumber),
    );
  }

  /// Show only the last 4 characters so a screen recording doesn't leak
  /// the full licence number. Apps like Uber/Rapido follow the same UX.
  static String _mask(String s) {
    if (s.isEmpty) return 'Not on file';
    if (s.length <= 4) return s;
    return '${'•' * (s.length - 4)}${s.substring(s.length - 4)}';
  }
}

class _StatusRow extends StatelessWidget {
  final String verificationStatus;
  const _StatusRow({required this.verificationStatus});

  @override
  Widget build(BuildContext context) {
    final isApproved = verificationStatus == 'approved';
    return _InfoRow(
      icon: isApproved ? Icons.verified : Icons.hourglass_bottom,
      iconColor: isApproved ? AppTheme.brand : AppTheme.warn,
      title: 'Verification',
      subtitle: switch (verificationStatus) {
        'approved' => 'Approved · you can accept trips',
        'pending' => 'Under review · usually within 24 hours',
        'rejected' => 'Rejected · contact support to re-apply',
        _ => verificationStatus,
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
