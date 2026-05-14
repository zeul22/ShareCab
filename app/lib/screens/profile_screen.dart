import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/auth_service.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.brandLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.brand,
                    child: Text(
                      (user?.name.characters.first ?? 'S').toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Guest',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.phone ?? '',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Tile(
              icon: Icons.history,
              title: 'Ride history',
              onTap: () => Navigator.of(context).pushNamed(Routes.history),
            ),
            _Tile(
              icon: Icons.shield_outlined,
              title: 'Help & safety',
              onTap: () => Navigator.of(context).pushNamed(Routes.helpSafety),
            ),
            _Tile(
              icon: Icons.payments_outlined,
              title: 'Payment methods',
              onTap: () {/* future */},
            ),
            _Tile(
              icon: Icons.logout,
              title: 'Log out',
              destructive: true,
              onTap: () async {
                final flow = context.read<RideFlowState>();
                // Explicit logout is rare in a logged-in-forever app —
                // when it does happen, treat any in-flight trip as
                // abandoned and cancel it server-side. Otherwise the
                // backend keeps a `requested` / `confirmed` trip alive
                // for the matching engine to hand to the now-departed
                // rider, and the co-rider sees a ghost in their group.
                //
                // cancelActiveRide is best-effort (it swallows network
                // errors) so logout doesn't hang on a flaky link.
                await flow.cancelActiveRide();
                // Belt + suspenders: cancelActiveRide doesn't reset
                // session id / search state, so do the full local wipe
                // before we sign the token out.
                flow.clearAfterClose();
                if (!context.mounted) return;
                await context.read<AuthService>().logout();
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(Routes.phoneEntry, (_) => false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: destructive ? Colors.red : AppTheme.brand),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: destructive ? Colors.red : null,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black26),
      onTap: onTap,
    );
  }
}
