class ApiConfig {
  // Override at build time:
  //   flutter run --dart-define=API_BASE_URL=https://api.sharecab.example
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000', // Android emulator -> host
  );

  static String get apiRoot => '$baseUrl/api';

  // MSG91 OTP widget credentials — both are CLIENT-side and safe to ship
  // in the binary (the widget is locked down to your bundle id in the
  // MSG91 console). The server-side `authkey` lives only on the backend
  // and is what actually validates the access token. Override per env:
  //   flutter run --dart-define=MSG91_WIDGET_ID=... \
  //               --dart-define=MSG91_AUTH_TOKEN=...
  // When EITHER value is missing the app falls back to the dev-OTP path
  // (HttpAuthApi + DEV_OTP) so local builds work without credentials.
  static const String msg91WidgetId = String.fromEnvironment(
    'MSG91_WIDGET_ID',
    defaultValue: '',
  );
  // MSG91's docs call this `authToken`; the SDK source calls it
  // `tokenAuth`. Accept either env name so users following the official
  // docs and users following the SDK source both work.
  static const String _msg91AuthToken = String.fromEnvironment(
    'MSG91_AUTH_TOKEN',
    defaultValue: '',
  );
  static const String _msg91TokenAuthLegacy = String.fromEnvironment(
    'MSG91_TOKEN_AUTH',
    defaultValue: '',
  );
  static String get msg91TokenAuth =>
      _msg91AuthToken.isNotEmpty ? _msg91AuthToken : _msg91TokenAuthLegacy;
  static bool get msg91Enabled =>
      msg91WidgetId.isNotEmpty && msg91TokenAuth.isNotEmpty;

  /// True when SOME but not all MSG91 dart-defines are set. This is
  /// almost always a misconfiguration (user has the auth token but
  /// forgot the widgetId, or vice versa) — the only path where it's
  /// fine is "no values set, dev mode". We surface partial states with
  /// a louder message so they don't get mistaken for a working setup.
  static bool get msg91PartiallyConfigured {
    final any = msg91WidgetId.isNotEmpty || msg91TokenAuth.isNotEmpty;
    return any && !msg91Enabled;
  }

  /// Human-readable explanation of why MSG91 is or isn't engaged.
  /// Logged once at startup so the running auth path is never a mystery.
  static String get msg91DiagnosticSummary {
    if (msg91Enabled) {
      return 'MSG91 OTP enabled (widgetId set, authToken set)';
    }
    final missing = <String>[
      if (msg91WidgetId.isEmpty) 'MSG91_WIDGET_ID',
      if (msg91TokenAuth.isEmpty) 'MSG91_AUTH_TOKEN',
    ];
    if (msg91PartiallyConfigured) {
      return 'MSG91 OTP MISCONFIGURED — partial config detected, falling back to dev-OTP. '
          'Missing --dart-define: ${missing.join(', ')}. '
          'You set one credential but not the other; both are required.';
    }
    return 'MSG91 OTP disabled — falling back to dev-OTP path. '
        'Missing --dart-define: ${missing.join(', ')}';
  }

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
