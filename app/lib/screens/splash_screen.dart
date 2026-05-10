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

    // Authed — pick the right home for the role. Drivers go to DriverHome
    // and skip the rider-side restoreActiveRide flow entirely (they have
    // their own active-dispatch surface inside DriverHome).
    final homeRoute = Routes.homeForRole(auth.user?.role);
    if (homeRoute == Routes.driverHome) {
      Navigator.of(context).pushReplacementNamed(Routes.driverHome);
      return;
    }

    // Rider path: see if there's an in-flight ride to resume. If so, push
    // Home first (so the user has a back-stack to fall back to) and then
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
