import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/api/driver_api.dart';
import '../services/auth_service.dart';
import '../services/location_push_service.dart';
import '../theme/app_theme.dart';

/// Bootstraps the session and routes to the right post-auth surface:
///   - not authed                → phone entry
///   - authed, no Driver doc     → onboarding wizard
///   - authed, status=pending    → pending review
///   - authed, status=approved   → home dashboard
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

    // Authed — figure out where the user belongs based on driver status.
    final driverApi = context.read<DriverApi>();
    try {
      final profile = await driverApi.getMyDriverOrNull();
      if (!mounted) return;
      if (profile == null) {
        Navigator.of(context).pushReplacementNamed(Routes.onboarding);
        return;
      }
      // Heal a stale JWT: if the server has us as a driver but our cached
      // session still says rider (e.g. onboarding completed on an older
      // build that didn't refresh), mint a fresh token so the
      // requireRole('driver') gates on /online + /offline don't 403.
      if (auth.user?.role != 'driver') {
        await auth.forceRefresh();
        if (!mounted) return;
      }
      if (profile.verificationStatus == 'approved') {
        // Resume location pings if the driver was online when they last
        // closed the app — otherwise riders see a stale position until
        // they toggle off/on. HomeScreen's _refresh also covers this
        // belt-and-suspenders, but starting here avoids the ~12s window
        // before the first poll completes.
        if (profile.isOnline) {
          unawaited(context.read<LocationPushService>().start());
        }
        Navigator.of(context).pushReplacementNamed(Routes.home);
      } else {
        Navigator.of(context).pushReplacementNamed(Routes.pendingReview);
      }
    } catch (_) {
      // Network blip on first launch — drop to onboarding rather than
      // strand the user on the splash. They can retry from there.
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(Routes.onboarding);
      }
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
              'ShareCab Driver',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Drive with ShareCab. Earn on every trip.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
