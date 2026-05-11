import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  // Override at build time:
  //   flutter run --dart-define=API_BASE_URL=https://api.sharecab.example
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000', // Android emulator -> host
  );

  static String get apiRoot => '$baseUrl/api';

  // MSG91 OTP widget credentials. These are CLIENT-side values by design;
  // the server-side `MSG91_AUTH_KEY` is separate and must never ship in
  // Flutter. Credentials can be provided either at build time:
  //   flutter run --dart-define=MSG91_WIDGET_ID=... \
  //               --dart-define=MSG91_WIDGET_AUTH_TOKEN=...
  // or by the backend's public /auth/otp/msg91/config endpoint.
  static const String _msg91WidgetIdFromDefine = String.fromEnvironment(
    'MSG91_WIDGET_ID',
    defaultValue: '',
  );
  // MSG91's docs call this `authToken`; the SDK source calls it
  // `tokenAuth`. Accept either env name so users following the official
  // docs and users following the SDK source both work.
  static const String _msg91WidgetAuthToken = String.fromEnvironment(
    'MSG91_WIDGET_AUTH_TOKEN',
    defaultValue: '',
  );
  static const String _msg91AuthToken = String.fromEnvironment(
    'MSG91_AUTH_TOKEN',
    defaultValue: '',
  );
  static const String _msg91TokenAuthLegacy = String.fromEnvironment(
    'MSG91_TOKEN_AUTH',
    defaultValue: '',
  );
  static String _runtimeMsg91WidgetId = '';
  static String _runtimeMsg91AuthToken = '';
  static bool _runtimeMsg91ConfigLoaded = false;

  static String get msg91WidgetId => _msg91WidgetIdFromDefine.isNotEmpty
      ? _msg91WidgetIdFromDefine
      : _runtimeMsg91WidgetId;
  static String get msg91TokenAuth {
    if (_msg91WidgetAuthToken.isNotEmpty) return _msg91WidgetAuthToken;
    if (_msg91AuthToken.isNotEmpty) return _msg91AuthToken;
    if (_msg91TokenAuthLegacy.isNotEmpty) return _msg91TokenAuthLegacy;
    return _runtimeMsg91AuthToken;
  }

  static bool get msg91Enabled =>
      msg91WidgetId.isNotEmpty && msg91TokenAuth.isNotEmpty;

  static Future<void> loadRuntimeMsg91Config({http.Client? client}) async {
    if (msg91Enabled || _runtimeMsg91ConfigLoaded) return;
    _runtimeMsg91ConfigLoaded = true;

    final c = client ?? http.Client();
    try {
      final res = await c.get(Uri.parse('$apiRoot/auth/otp/msg91/config'));
      if (res.statusCode < 200 || res.statusCode >= 300 || res.body.isEmpty) {
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['enabled'] != true) return;
      final widgetId = body['widgetId'];
      final authToken = body['authToken'] ?? body['tokenAuth'];
      if (widgetId is String && authToken is String) {
        _runtimeMsg91WidgetId = widgetId;
        _runtimeMsg91AuthToken = authToken;
      }
    } catch (e) {
      debugPrint('[auth] MSG91 runtime config fetch failed: $e');
    } finally {
      if (client == null) c.close();
    }
  }

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
      final source = _msg91WidgetIdFromDefine.isNotEmpty ||
              _msg91WidgetAuthToken.isNotEmpty ||
              _msg91AuthToken.isNotEmpty ||
              _msg91TokenAuthLegacy.isNotEmpty
          ? 'dart-define'
          : 'backend config';
      return 'MSG91 OTP enabled (widgetId set, authToken set via $source)';
    }
    final missing = <String>[
      if (msg91WidgetId.isEmpty) 'MSG91_WIDGET_ID',
      if (msg91TokenAuth.isEmpty) 'MSG91_WIDGET_AUTH_TOKEN',
    ];
    if (msg91PartiallyConfigured) {
      return 'MSG91 OTP MISCONFIGURED — partial config detected, falling back to dev-OTP. '
          'Missing widget config: ${missing.join(', ')}. '
          'Set both credentials via dart-define or backend config.';
    }
    return 'MSG91 OTP disabled — falling back to dev-OTP path. '
        'Missing widget config: ${missing.join(', ')}';
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
    defaultValue: '***REMOVED_GOOGLE_MAPS_KEY***',
  );
}
