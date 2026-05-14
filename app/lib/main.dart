import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

import 'routes.dart';
import 'services/ad_service.dart';
import 'services/api/auth_api.dart';
import 'services/api/dynamic_auth_api.dart';
import 'services/api/http_ride_api.dart';
import 'services/api/ride_api.dart';
import 'services/auth_service.dart';
import 'services/chat_unread_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/ride_flow.dart';
import 'widgets/co_rider_rating_dialog.dart';
import 'services/trip_tracking_service.dart';
import 'theme/app_theme.dart';
import 'utils/api_config.dart';
import 'utils/locale_policy.dart';
import 'widgets/ride_flow_banner.dart';

import 'screens/airport_arrival_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/destination_screen.dart';
import 'screens/help_safety_screen.dart';
import 'screens/home_screen.dart';
import 'screens/luggage_screen.dart';
import 'screens/match_preference_screen.dart';
import 'screens/match_result_screen.dart';
import 'screens/onboarding_screen.dart';
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
    // DynamicAuthApi re-checks msg91Enabled per call (and best-effort
    // refreshes the runtime config from the backend each request), so a
    // late-arriving config — e.g. backend started after the app — still
    // routes the next OTP request through the MSG91 widget instead of
    // staying stuck on the dev-OTP HTTP path.
    final AuthApi authApi = DynamicAuthApi();
    final authService = AuthService(authApi);
    final RideApi rideApi = HttpRideApi(
      tokenGetter: authService.accessTokenForApi,
    );

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
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider(create: (_) => LocationService(rideApi: rideApi)),
        ChangeNotifierProvider(create: (_) => RideFlowState(rideApi)),
        // Live-trip tracker: polls /trips/:id/driver-location while the
        // rider is on the RideStatusScreen. Cheap to keep around even
        // when idle — no timer runs until start() is called.
        ChangeNotifierProvider(create: (_) => TripTrackingService(rideApi)),
        // App-lifetime unread-message counter. Watches RideFlowState
        // for the active group and keeps one socket subscription
        // alive there so the chat-button badge updates while the
        // rider is on any other screen.
        ChangeNotifierProxyProvider<RideFlowState, ChatUnreadService>(
          // Eager: without this the service stays uninstantiated until
          // the first widget reads it (typically the chat-button badge
          // on coordination/confirmation), which means any chat:message
          // broadcast BEFORE the rider lands on that screen is missed
          // and the badge starts at 0. Eager construction makes the
          // service listen for messages from the moment the auth
          // session + ride flow are wired up.
          lazy: false,
          create: (_) => ChatUnreadService(authService),
          update: (_, flow, service) {
            final s = service ?? ChatUnreadService(authService);
            s.attachFlow(flow);
            return s;
          },
        ),
      ],
      child: MaterialApp(
        title: 'ShareCab',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        supportedLocales: ShareCabLocalePolicy.supportedLocales,
        localeResolutionCallback: ShareCabLocalePolicy.resolve,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        navigatorKey: navigatorKey,
        navigatorObservers: [routeObserver],
        // The builder wraps every screen with a bottom-floating banner that
        // surfaces "still searching" / "match found" / "ride in progress"
        // state app-wide, so the rider can navigate around while a search
        // is in flight without losing track of it.
        //
        // _CoRiderRatingPump lives in the same wrapper so the rating
        // dialog can pop over any screen — when a sibling's leg
        // completes mid-flow, the polling watcher refills the queue
        // and the pump opens the dialog wherever the user happens
        // to be.
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
            _CoRiderRatingPump(navigatorKey: navigatorKey),
          ],
        ),
        initialRoute: Routes.splash,
        routes: {
          Routes.splash: (_) => const SplashScreen(),
          Routes.phoneEntry: (_) => const PhoneEntryScreen(),
          Routes.otpVerify: (_) => const OtpVerifyScreen(),
          Routes.onboarding: (_) => const OnboardingScreen(),
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

/// Top-level pump that opens the [CoRiderRatingDialog] over whatever
/// screen is on top whenever [RideFlowState.pendingCoRiderRatings]
/// becomes non-empty. Sits in the MaterialApp builder so it has
/// access to the navigator + provider scope without needing screens
/// to opt in individually.
///
/// Concurrency: shows only one dialog at a time. While a dialog is
/// open the pump no-ops on listener fires; when the dialog closes
/// the pump dequeues, calls a fresh refresh, and re-checks the
/// queue so back-to-back prompts surface naturally.
class _CoRiderRatingPump extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const _CoRiderRatingPump({required this.navigatorKey});

  @override
  State<_CoRiderRatingPump> createState() => _CoRiderRatingPumpState();
}

class _CoRiderRatingPumpState extends State<_CoRiderRatingPump> {
  RideFlowState? _flow;
  bool _dialogOpen = false;
  Timer? _periodic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final flow = context.read<RideFlowState>();
    if (_flow != flow) {
      _flow?.removeListener(_onFlowChanged);
      _flow = flow;
      flow.addListener(_onFlowChanged);
      // First pump on attach so we surface anything that was already
      // pending when the app launched (rider re-opened the app after
      // a previous ride ended).
      flow.pumpPendingCoRiderRatings();
    }
    // Background refresh while the rider app is foregrounded. 8s
    // is tight enough that when one co-rider closes shortly after
    // the other, the second close surfaces on the first's screen
    // before the user gives up waiting. Cost: one cheap GET per 8s,
    // server-side filtered, no payload on the empty case.
    //
    // (Was 60s — but with the active-trip polling watcher stopping
    // on close, the first-to-close rider would wait up to a full
    // minute for the second rider's dialog to appear.)
    _periodic ??= Timer.periodic(
      const Duration(seconds: 8),
      (_) => _flow?.pumpPendingCoRiderRatings(),
    );
  }

  void _onFlowChanged() {
    if (!mounted || _dialogOpen) return;
    final flow = _flow;
    if (flow == null) return;
    final queue = flow.pendingCoRiderRatings;
    if (queue.isEmpty) return;
    // Defer to the next frame so we don't try to open a dialog
    // mid-build of the widget tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNext());
  }

  Future<void> _showNext() async {
    if (_dialogOpen) return;
    final flow = _flow;
    if (flow == null) return;
    final queue = flow.pendingCoRiderRatings;
    if (queue.isEmpty) return;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;

    _dialogOpen = true;
    try {
      await CoRiderRatingDialog.show(ctx, pending: queue.first);
    } finally {
      _dialogOpen = false;
      flow.dequeuePendingCoRiderRating();
      // Re-pump in case the user's rate/skip altered the queue OR a
      // co-rider's leg completed while the dialog was open.
      flow.pumpPendingCoRiderRatings();
    }
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _flow?.removeListener(_onFlowChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
