/// Holds form data across the multi-step onboarding wizard. A plain class
/// (not a Provider) — the wizard widget owns one instance for its lifetime
/// and threads it into each step. No need to broadcast changes; each step
/// is rebuilt on navigation.
class OnboardingState {
  // Step 1 — personal
  String fullName = '';
  String email = '';

  // Step 2 — vehicle
  String licenseNumber = '';
  String vehicleModel = '';
  String plate = '';
  String color = '';
  int capacity = 4;

  /// Stubbed for the v1 wizard — file paths if/when the user attaches
  /// photos. We don't upload them yet (the backend endpoint accepts the
  /// text fields only), but the UI surfaces the attach affordance so
  /// drivers see the same flow they get from Rapido/Ola.
  String? licensePhotoPath;
  String? rcPhotoPath;
  String? selfiePhotoPath;
}
