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

    // Authed — see if there's an in-flight ride to resume. If so, push
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
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'S',
                style: TextStyle(
                  color: AppTheme.brand,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ShareCab',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
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
