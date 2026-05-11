import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

import 'routes.dart';
import 'services/ad_service.dart';
import 'services/api/auth_api.dart';
import 'services/api/driver_api.dart';
import 'services/api/http_auth_api.dart';
import 'services/api/http_ride_api.dart';
import 'services/api/msg91_auth_api.dart';
import 'services/api/ride_api.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/ride_flow.dart';
import 'theme/app_theme.dart';
import 'utils/api_config.dart';
import 'widgets/ride_flow_banner.dart';

import 'screens/airport_arrival_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/destination_screen.dart';
import 'screens/driver_active_trip_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/help_safety_screen.dart';
import 'screens/home_screen.dart';
import 'screens/luggage_screen.dart';
import 'screens/match_preference_screen.dart';
import 'screens/match_result_screen.dart';
import 'screens/otp_verify_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/phone_entry_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rating_screen.dart';
import 'screens/ride_completed_screen.dart';
import 'screens/ride_confirmation_screen.dart';
import 'screens/ride_history_screen.dart';
import 'screens/ride_status_screen.dart';
import 'screens/rider_coordination_screen.dart';
import 'screens/route_stops_screen.dart';
import 'screens/searching_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  // Required before any plugin-channel call (incl. NotificationService.init).
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: notification init is wrapped in try/catch so a failed
  // permission grant or unavailable channel doesn't block app launch.
  await NotificationService.instance.init();
  // MSG91 OTP widget init. Credentials can come from --dart-define or
  // the backend's public widget-config endpoint; otherwise the app falls
  // back to the dev-OTP path so local builds work without a real account.
  await ApiConfig.loadRuntimeMsg91Config();
  if (ApiConfig.msg91Enabled) {
    OTPWidget.initializeWidget(
      ApiConfig.msg91WidgetId,
      ApiConfig.msg91TokenAuth,
    );
  }
  // AdMob SDK init — fires the underlying MobileAds.initialize() so the
  // first rewarded-ad load is hot. Failures here are non-fatal; the
  // unlock sheet falls back to the pay path if ads fail to serve.
  await AdService.instance.init();
  // Print which auth path is engaged so a silent fallback to dev-OTP
  // is impossible to miss while debugging.
  debugPrint('[auth] ${ApiConfig.msg91DiagnosticSummary}');
  runApp(const ShareCabApp());
}

/// Tracks the topmost route name in a [ValueNotifier] so the global
/// [RideFlowBanner] can hide itself when the user is already on the screen
/// that natively renders that state.
class _CurrentRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> currentRoute = ValueNotifier<String?>(null);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute.value = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute.value = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRoute.value = newRoute?.settings.name;
  }
}

class ShareCabApp extends StatelessWidget {
  const ShareCabApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Live API bindings — talk to the ShareCab backend at ApiConfig.apiRoot.
    // AuthService is built before RideApi so the latter can borrow the
    // token getter and the current rider's id (needed for unlock minting).
    //
    // MSG91 wiring: when widgetId + tokenAuth are configured, the OTP
    // send/verify happens client-side via the MSG91 SDK and the resulting
    // access token is exchanged at our backend's /auth/otp/msg91/verify.
    // Refresh + logout still go through HttpAuthApi (delegated by
    // Msg91AuthApi). Without credentials we fall back to HttpAuthApi's
    // dev-OTP path so local demos keep working.
    final AuthApi authApi =
        ApiConfig.msg91Enabled ? Msg91AuthApi() : HttpAuthApi();
    final authService = AuthService(authApi);
    final RideApi rideApi = HttpRideApi(
      tokenGetter: authService.accessTokenForApi,
      riderIdGetter: () => authService.user?.id,
    );
    // DriverApi piggy-backs on the same auth session — its tokenGetter
    // hands out the rider/driver-agnostic access token. Provided at the
    // root so DriverHomeScreen + future driver-side screens share one
    // instance (and therefore one underlying http.Client).
    final driverApi = DriverApi(tokenGetter: authService.accessTokenForApi);

    // Navigator key + route observer power the global RideFlowBanner: the
    // banner sits above the Navigator in the widget tree (so it can overlay
    // every screen) and uses these to (a) know which route is on top and
    // (b) push the appropriate destination when tapped.
    final navigatorKey = GlobalKey<NavigatorState>();
    final routeObserver = _CurrentRouteObserver();

    return MultiProvider(
      providers: [
        Provider<AuthApi>.value(value: authApi),
        Provider<RideApi>.value(value: rideApi),
        Provider<DriverApi>.value(value: driverApi),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => RideFlowState(rideApi)),
      ],
      child: MaterialApp(
        title: 'ShareCab',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        navigatorKey: navigatorKey,
        navigatorObservers: [routeObserver],
        // The builder wraps every screen with a bottom-floating banner that
        // surfaces "still searching" / "match found" / "ride in progress"
        // state app-wide, so the rider can navigate around while a search
        // is in flight without losing track of it.
        builder: (_, child) => Stack(
          children: [
            child!,
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: RideFlowBanner(
                currentRoute: routeObserver.currentRoute,
                navigatorKey: navigatorKey,
              ),
            ),
          ],
        ),
        initialRoute: Routes.splash,
        routes: {
          Routes.splash: (_) => const SplashScreen(),
          Routes.phoneEntry: (_) => const PhoneEntryScreen(),
          Routes.otpVerify: (_) => const OtpVerifyScreen(),
          Routes.home: (_) => const HomeScreen(),
          Routes.driverHome: (_) => const DriverHomeScreen(),
          Routes.driverActiveTrip: (_) => const DriverActiveTripScreen(),
          Routes.profile: (_) => const ProfileScreen(),
          Routes.helpSafety: (_) => const HelpSafetyScreen(),
          Routes.planRide: (_) => const DestinationScreen(),
          Routes.airportArrival: (_) => const AirportArrivalScreen(),
          Routes.luggage: (_) => const LuggageScreen(),
          Routes.matchPreference: (_) => const MatchPreferenceScreen(),
          Routes.searching: (_) => const SearchingScreen(),
          Routes.matchResult: (_) => const MatchResultScreen(),
          Routes.routeStops: (_) => const RouteStopsScreen(),
          Routes.rideConfirmation: (_) => const RideConfirmationScreen(),
          Routes.riderCoordination: (_) => const RiderCoordinationScreen(),
          Routes.liveRide: (_) => const RideStatusScreen(),
          Routes.payment: (_) => const PaymentScreen(),
          Routes.rideCompleted: (_) => const RideCompletedScreen(),
          Routes.rating: (_) => const RatingScreen(),
          Routes.history: (_) => const RideHistoryScreen(),
        },
        // ChatScreen takes a required groupId, so it can't live in the
        // const-builder routes map above. Push via:
        //   Navigator.pushNamed(Routes.chat, arguments: groupId)
        onGenerateRoute: (settings) {
          if (settings.name == Routes.chat) {
            final groupId = settings.arguments as String?;
            if (groupId == null || groupId.isEmpty) return null;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ChatScreen(groupId: groupId),
            );
          }
          return null;
        },
      ),
    );
  }
}
