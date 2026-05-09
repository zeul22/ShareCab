class ApiConfig {
  // Override at build time:
  //   flutter run --dart-define=API_BASE_URL=https://api.sharecab.example
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000', // Android emulator -> host
  );

  static String get apiRoot => '$baseUrl/api';

  // Google Maps Platform API key — used by the Places autocomplete widget.
  // Native map rendering uses the keys configured in the Android/iOS native
  // projects (AndroidManifest.xml + ios/Runner/Info.plist).
  //
  // The default is the same demo key we ship in the native configs. It's
  // restricted in Google Cloud Console (Android pkg + SHA-1 / iOS bundle ID),
  // safe to commit, and lets `flutter run` work without --dart-define.
  // Override per-environment with:
  //   flutter run --dart-define=GOOGLE_MAPS_KEY=AIza...
  // Rotate before going to production; see .vscode/launch.json.
  static const String googleMapsKey = String.fromEnvironment(
    'GOOGLE_MAPS_KEY',
    defaultValue: 'AIzaSyBWOhx-MTodQ3_mgUgi9ZTPK0ths1XaSNk',
  );
}
