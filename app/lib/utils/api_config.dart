class ApiConfig {
  // Override at build time:
  //   flutter run --dart-define=API_BASE_URL=https://api.sharecab.example
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000', // Android emulator -> host
  );

  static String get apiRoot => '$baseUrl/api';

  // Google Maps Platform API key — used by the Places autocomplete widget on
  // both platforms. Native map rendering uses the keys configured in the
  // Android/iOS native projects (see app/README.md). Pass at build time:
  //   flutter run --dart-define=GOOGLE_MAPS_KEY=AIza...
  static const String googleMapsKey = String.fromEnvironment(
    'GOOGLE_MAPS_KEY',
    defaultValue: '',
  );
}
