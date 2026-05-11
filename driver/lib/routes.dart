/// Centralized route names. Single source of truth so renames stay local.
class Routes {
  const Routes._();

  static const splash = '/';
  static const phoneEntry = '/auth/phone';
  static const otpVerify = '/auth/otp';

  // Onboarding wizard — Rapido/Uber/Ola-style multi-step driver signup.
  // Distinct from /home because we need to gate access: a logged-in user
  // without a Driver record (or with verificationStatus != 'approved')
  // can't reach the home screen.
  static const onboarding = '/onboarding';
  static const pendingReview = '/pending-review';

  // Steady-state for an approved driver.
  static const home = '/home';
  static const activeTrip = '/active-trip';
  static const profile = '/profile';
}
