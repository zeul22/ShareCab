import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/auth_service.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthService>();
    await auth.bootstrap();
    if (!mounted) return;

    if (!auth.isAuthenticated) {
      Navigator.of(context).pushReplacementNamed(Routes.phoneEntry);
      return;
    }

    // Authed but onboarding incomplete (brand-new rider whose phone
    // was verified but who hasn't supplied name + email yet, or an
    // existing user pre-dating the onboarding gate). Park them on the
    // form — restoreActiveRide can wait until they have an identity.
    final user = auth.user;
    if (user != null && !user.profileCompleted) {
      Navigator.of(context).pushReplacementNamed(Routes.onboarding);
      return;
    }

    // Both rider- and driver-role users can use this app as a rider —
    // a driver booking a cab for themselves is a perfectly normal flow
    // and the backend's rider endpoints (POST /trips, matching, chat,
    // ratings) only need requireAuth, not requireRole('rider'). The
    // driver-specific surfaces (online/offline, dispatch, offers, trip
    // lifecycle) live in the separate /driver app; this app just runs
    // them through the rider flow.

    // See if there's an in-flight ride to resume. If so, push Home
    // first (so the user has a back-stack to fall back to) and then
    // jump forward to the active screen. If not, just land on Home.
    final flow = context.read<RideFlowState>();
    final resumeRoute = await flow.restoreActiveRide();
    if (!mounted) return;

    if (resumeRoute != null) {
      Navigator.of(context).pushReplacementNamed(Routes.home);
      Navigator.of(context).pushNamed(resumeRoute);
    } else {
      Navigator.of(context).pushReplacementNamed(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.brand,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Square app icon on a white rounded tile so it reads cleanly
            // against the brand-coloured background. 96px matches the
            // visual weight of the original "S" placeholder while still
            // letting the icon detail be legible.
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/appIcon.png',
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ShareCab',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share the cab. Split the fare.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
