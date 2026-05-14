/// Centralized route names. Imported by `main.dart` and any caller of
/// `Navigator.pushNamed` so renames stay in one place.
///
/// This binary is the *rider* surface — it hosts the booking flow,
/// matching, chat, and live-ride screens. Driver-only surfaces (online/
/// offline, dispatch, accepting offers, trip lifecycle) live in the
/// separate /driver app. A driver-role user signing in here is fine
/// though: they get the rider experience and can book a cab for
/// themselves like anyone else.
class Routes {
  const Routes._();

  static const splash = '/';
  static const phoneEntry = '/auth/phone';
  static const otpVerify = '/auth/otp';
  // First-time rider onboarding — name + email. Routed to from splash
  // + OTP-verify when AuthService.user.profileCompleted is false.
  static const onboarding = '/onboarding';

  static const home = '/home';
  static const profile = '/profile';
  static const helpSafety = '/help';

  // Booking flow
  static const planRide = '/plan';
  static const airportArrival = '/airport';
  static const luggage = '/luggage';
  static const matchPreference = '/match-preference';
  static const searching = '/searching';
  static const matchResult = '/match';
  static const routeStops = '/route-stops';
  static const rideConfirmation = '/confirm';
  // Rider-only mode landing screen — used when there's no driver to
  // dispatch. Replaces RideConfirmation + RideStatus while we're still
  // bootstrapping driver supply.
  static const riderCoordination = '/rider-coordination';
  static const chat = '/chat';
  static const liveRide = '/ride';
  static const payment = '/payment';
  static const rideCompleted = '/completed';
  static const rating = '/rating';

  static const history = '/history';
}
