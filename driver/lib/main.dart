import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

import 'routes.dart';
import 'screens/active_trip_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/otp_verify_screen.dart';
import 'screens/pending_review_screen.dart';
import 'screens/phone_entry_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api/auth_api.dart';
import 'services/api/driver_api.dart';
import 'services/api/http_auth_api.dart';
import 'services/api/msg91_auth_api.dart';
import 'services/auth_service.dart';
import 'services/location_push_service.dart';
import 'theme/app_theme.dart';
import 'utils/api_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pulls MSG91 widget creds from the backend if --dart-defines aren't set.
  // Falls back silently when the backend isn't reachable — auth then runs
  // through HttpAuthApi's dev-OTP path.
  await ApiConfig.loadRuntimeMsg91Config();
  if (ApiConfig.msg91Enabled) {
    OTPWidget.initializeWidget(
      ApiConfig.msg91WidgetId,
      ApiConfig.msg91TokenAuth,
    );
  }
  debugPrint('[auth] ${ApiConfig.msg91DiagnosticSummary}');
  runApp(const ShareCabDriverApp());
}

class ShareCabDriverApp extends StatelessWidget {
  const ShareCabDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Auth API is MSG91-backed when creds are configured; otherwise the
    // backend's dev-OTP fallback kicks in. AuthService persists the session
    // and powers token refresh for DriverApi.
    final AuthApi authApi =
        ApiConfig.msg91Enabled ? Msg91AuthApi() : HttpAuthApi();
    final authService = AuthService(authApi);
    final driverApi = DriverApi(tokenGetter: authService.accessTokenForApi);
    // Location push uses the same DriverApi instance so it shares the auth
    // header logic and underlying http.Client. One singleton for the whole
    // app lifetime — start/stop is controlled by the online toggle.
    final locationPush = LocationPushService(api: driverApi);

    return MultiProvider(
      providers: [
        Provider<AuthApi>.value(value: authApi),
        Provider<DriverApi>.value(value: driverApi),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<LocationPushService>.value(value: locationPush),
      ],
      child: MaterialApp(
        title: 'ShareCab Driver',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: Routes.splash,
        routes: {
          Routes.splash: (_) => const SplashScreen(),
          Routes.phoneEntry: (_) => const PhoneEntryScreen(),
          Routes.otpVerify: (_) => const OtpVerifyScreen(),
          Routes.onboarding: (_) => const OnboardingScreen(),
          Routes.pendingReview: (_) => const PendingReviewScreen(),
          Routes.home: (_) => const HomeScreen(),
          Routes.activeTrip: (_) => const ActiveTripScreen(),
          Routes.profile: (_) => const ProfileScreen(),
        },
      ),
    );
  }
}
