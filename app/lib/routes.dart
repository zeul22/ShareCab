/// Centralized route names. Imported by `main.dart` and any caller of
/// `Navigator.pushNamed` so renames stay in one place.
class Routes {
  const Routes._();

  static const splash = '/';
  static const phoneEntry = '/auth/phone';
  static const otpVerify = '/auth/otp';

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
  static const chat = '/chat';
  static const liveRide = '/ride';
  static const payment = '/payment';
  static const rideCompleted = '/completed';
  static const rating = '/rating';

  static const history = '/history';
}
