import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'routes.dart';
import 'services/api/auth_api.dart';
import 'services/api/http_auth_api.dart';
import 'services/api/http_ride_api.dart';
import 'services/api/ride_api.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/ride_flow.dart';
import 'theme/app_theme.dart';

import 'screens/airport_arrival_screen.dart';
import 'screens/destination_screen.dart';
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
import 'screens/route_stops_screen.dart';
import 'screens/searching_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const ShareCabApp());
}

class ShareCabApp extends StatelessWidget {
  const ShareCabApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Live API bindings — talk to the ShareCab backend at ApiConfig.apiRoot.
    // AuthService is built before RideApi so the latter can borrow the
    // token getter and the current rider's id (needed for unlock minting).
    final AuthApi authApi = HttpAuthApi();
    final authService = AuthService(authApi);
    final RideApi rideApi = HttpRideApi(
      tokenGetter: authService.accessTokenForApi,
      riderIdGetter: () => authService.user?.id,
    );

    return MultiProvider(
      providers: [
        Provider<AuthApi>.value(value: authApi),
        Provider<RideApi>.value(value: rideApi),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => RideFlowState(rideApi)),
      ],
      child: MaterialApp(
        title: 'ShareCab',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: Routes.splash,
        routes: {
          Routes.splash: (_) => const SplashScreen(),

          Routes.phoneEntry: (_) => const PhoneEntryScreen(),
          Routes.otpVerify: (_) => const OtpVerifyScreen(),

          Routes.home: (_) => const HomeScreen(),
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
          Routes.liveRide: (_) => const RideStatusScreen(),
          Routes.payment: (_) => const PaymentScreen(),
          Routes.rideCompleted: (_) => const RideCompletedScreen(),
          Routes.rating: (_) => const RatingScreen(),

          Routes.history: (_) => const RideHistoryScreen(),
        },
      ),
    );
  }
}
