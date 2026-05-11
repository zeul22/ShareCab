import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Driver-app build-time configuration. Mirrors the rider app's
/// `ApiConfig` so the two clients stay aligned on backend URLs + MSG91
/// widget credentials. Kept as a separate file (not a shared package)
/// because the driver app has a different feature surface — no Google
/// Maps key, no AdMob unit ids, etc.
class ApiConfig {
  /// Override at build time:
  ///   flutter run --dart-define=API_BASE_URL=https://api.sharecab.example
  /// Default is the Android emulator's host loopback so `flutter run`
  /// against a local backend Just Works.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  static String get apiRoot => '$baseUrl/api';

  // MSG91 OTP widget credentials. Client-side values by design — the
  // server-side MSG91_AUTH_KEY never ships in Flutter. Provided either
  // at build time (--dart-define) or via the backend's public widget
  // config endpoint. Missing credentials drop the app into the
  // dev-OTP path on the backend.
  static const String _msg91WidgetIdFromDefine = String.fromEnvironment(
    'MSG91_WIDGET_ID',
    defaultValue: '',
  );
  static const String _msg91WidgetAuthToken = String.fromEnvironment(
    'MSG91_WIDGET_AUTH_TOKEN',
    defaultValue: '',
  );
  static const String _msg91AuthToken = String.fromEnvironment(
    'MSG91_AUTH_TOKEN',
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

  /// Logged once at startup so the running auth path is never a mystery.
  static String get msg91DiagnosticSummary {
    if (msg91Enabled) {
      return 'MSG91 OTP enabled (widget configured)';
    }
    return 'MSG91 OTP disabled — falling back to dev-OTP path on backend.';
  }

  // Google Maps Platform API key — used by RouteService for the Directions
  // API (decoded polyline along the trip stops). Native map rendering uses
  // the keys configured in the Android/iOS native projects.
  //
  // Default is the same demo key the rider app ships. Restricted in Google
  // Cloud Console (Android pkg + SHA-1 / iOS bundle ID), safe to commit.
  // Override per-environment with:
  //   flutter run --dart-define=GOOGLE_MAPS_KEY=AIza...
  static const String googleMapsKey = String.fromEnvironment(
    'GOOGLE_MAPS_KEY',
    defaultValue: '***REMOVED_GOOGLE_MAPS_KEY***',
  );
}
