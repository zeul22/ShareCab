/// Centralized route names. Imported by `main.dart` and any caller of
/// `Navigator.pushNamed` so renames stay in one place.
class Routes {
  const Routes._();

  /// Single source of truth for "where does this user belong post-auth".
  /// Used by the splash + OTP-verify screens so we can't accidentally land
  /// a driver on the rider home (or vice-versa) from one of them.
  static String homeForRole(String? role) =>
      role == 'driver' ? driverHome : home;

  static const splash = '/';
  static const phoneEntry = '/auth/phone';
  static const otpVerify = '/auth/otp';

  static const home = '/home';
  static const driverHome = '/driver/home';
  static const driverActiveTrip = '/driver/active';
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
