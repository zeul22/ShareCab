import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'utils/locale_policy.dart';

Future<void> main() async {
  // Wrap the whole boot in runZonedGuarded so any uncaught async error
  // (DNS failure, plugin init crash, provider exception, etc.) lands in
  // our logger instead of silently disconnecting the device.
  await runZonedGuarded(_bootstrap, (err, stack) {
    debugPrint('═══ FATAL (uncaught async) ═══');
    debugPrint('$err');
    debugPrint('$stack');
  });
}

Future<void> _bootstrap() async {
  debugPrint('[boot] 1/5 ensureInitialized()');
  WidgetsFlutterBinding.ensureInitialized();

  // Surface Flutter framework errors verbatim. Default behaviour in
  // debug is "red screen of error"; that doesn't show in the terminal,
  // so a layout / build exception elsewhere can look like a silent
  // disconnect. This forwards the full stack to stdout.
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('═══ FlutterError ═══');
    debugPrint(details.exceptionAsString());
    debugPrint('${details.stack}');
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('═══ PlatformDispatcher.onError ═══');
    debugPrint('$error');
    debugPrint('$stack');
    return true;
  };

  debugPrint('[boot] 2/5 loadRuntimeMsg91Config()');
  try {
    await ApiConfig.loadRuntimeMsg91Config();
  } catch (e, s) {
    debugPrint('[boot] MSG91 config load failed: $e\n$s');
  }

  debugPrint(
      '[boot] 3/5 OTPWidget init (msg91Enabled=${ApiConfig.msg91Enabled})');
  if (ApiConfig.msg91Enabled) {
    try {
      OTPWidget.initializeWidget(
        ApiConfig.msg91WidgetId,
        ApiConfig.msg91TokenAuth,
      );
    } catch (e, s) {
      debugPrint('[boot] OTPWidget.initializeWidget threw: $e\n$s');
    }
  }
  debugPrint('[auth] ${ApiConfig.msg91DiagnosticSummary}');

  debugPrint('[boot] 4/5 runApp()');
  runApp(const ShareCabDriverApp());
  debugPrint('[boot] 5/5 runApp returned (UI engine running)');
}

class ShareCabDriverApp extends StatelessWidget {
  const ShareCabDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[boot] ShareCabDriverApp.build — constructing providers');
    // Auth API is MSG91-backed when creds are configured; otherwise the
    // backend's dev-OTP fallback kicks in. AuthService persists the session
    // and powers token refresh for DriverApi.
    final AuthApi authApi =
        ApiConfig.msg91Enabled ? Msg91AuthApi() : HttpAuthApi();
    debugPrint('[boot]   authApi = ${authApi.runtimeType}');
    final authService = AuthService(authApi);
    final driverApi = DriverApi(tokenGetter: authService.accessTokenForApi);
    // Location push uses the same DriverApi instance so it shares the auth
    // header logic and underlying http.Client. One singleton for the whole
    // app lifetime — start/stop is controlled by the online toggle.
    final locationPush = LocationPushService(api: driverApi);
    debugPrint('[boot]   providers ready — wiring MaterialApp');

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
        supportedLocales: ShareCabLocalePolicy.supportedLocales,
        localeResolutionCallback: ShareCabLocalePolicy.resolve,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
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
