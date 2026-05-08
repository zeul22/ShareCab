import 'dart:convert';

import 'package:http/http.dart' as http;

/// One autocomplete suggestion from the Places API.
class PlacePrediction {
  final String placeId;
  final String description;

  /// Optional one-line "main" text (e.g. business name) when available.
  final String primaryText;

  /// Optional secondary line (e.g. city, country).
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    this.primaryText = '',
    this.secondaryText = '',
  });
}

/// A resolved place — what we keep after the user picks a prediction.
class PlaceDetails {
  final String placeId;
  final String formattedAddress;
  final double lat;
  final double lng;

  const PlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
  });
}

/// Direct client for **Places API (New)** — `places.googleapis.com/v1/...`.
///
/// We replaced `google_places_flutter` with this because the package crashes
/// (null check operator) on any non-OK response from Google. Calling the API
/// ourselves means:
///   - No surprise crashes; failures are exceptions our UI can show.
///   - One dependency fewer in pubspec.yaml.
///   - We use the modern API endpoint, not the deprecated legacy one.
///
/// Required setup on the GCP project:
///   1. Enable **Places API (New)**:
///      https://console.developers.google.com/apis/api/places.googleapis.com
///   2. Application restrictions on the key should include the iOS bundle ID
///      and Android package name, or be set to "None" while developing.
class PlacesService {
  final String apiKey;
  final http.Client _client;

  PlacesService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  static const _autocompleteUrl = 'https://places.googleapis.com/v1/places:autocomplete';
  static const _detailsUrlBase = 'https://places.googleapis.com/v1/places/';

  /// Field mask tells Google which fields to include in the response. Smaller
  /// masks = lower per-request cost.
  static const _detailsFieldMask =
      'id,formattedAddress,location,displayName';

  bool get isConfigured => apiKey.isNotEmpty;

  Future<List<PlacePrediction>> autocomplete(String query) async {
    if (!isConfigured) return const [];
    final input = query.trim();
    if (input.isEmpty) return const [];

    final res = await _client.post(
      Uri.parse(_autocompleteUrl),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
      },
      body: jsonEncode({'input': input}),
    );

    if (res.statusCode != 200) {
      throw _PlacesException.fromResponse(res);
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final suggestions = (body['suggestions'] as List?) ?? const [];

    return suggestions
        .map((raw) => raw as Map<String, dynamic>)
        .map((m) => m['placePrediction'] as Map<String, dynamic>?)
        .where((p) => p != null)
        .map((p) => p!)
        .map((p) {
      final structured =
          (p['structuredFormat'] as Map<String, dynamic>?) ?? const {};
      final main = (structured['mainText'] as Map<String, dynamic>?)?['text'] as String?;
      final secondary =
          (structured['secondaryText'] as Map<String, dynamic>?)?['text'] as String?;
      return PlacePrediction(
        placeId: (p['placeId'] as String?) ?? '',
        description: (p['text'] as Map<String, dynamic>?)?['text'] as String? ??
            main ??
            '',
        primaryText: main ?? '',
        secondaryText: secondary ?? '',
      );
    }).where((p) => p.placeId.isNotEmpty).toList(growable: false);
  }

  Future<PlaceDetails?> details(String placeId) async {
    if (!isConfigured || placeId.isEmpty) return null;

    final res = await _client.get(
      Uri.parse('$_detailsUrlBase$placeId'),
      headers: {
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': _detailsFieldMask,
      },
    );

    if (res.statusCode != 200) {
      throw _PlacesException.fromResponse(res);
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final loc = body['location'] as Map<String, dynamic>?;
    if (loc == null) return null;

    return PlaceDetails(
      placeId: (body['id'] as String?) ?? placeId,
      formattedAddress: (body['formattedAddress'] as String?) ?? '',
      lat: (loc['latitude'] as num?)?.toDouble() ?? 0,
      lng: (loc['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  void dispose() => _client.close();
}

class _PlacesException implements Exception {
  final int statusCode;
  final String message;

  const _PlacesException(this.statusCode, this.message);

  factory _PlacesException.fromResponse(http.Response res) {
    String message = 'Places API ${res.statusCode}';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      final m = err?['message'] as String?;
      if (m != null) message = m;
    } catch (_) {/* keep the default */}
    return _PlacesException(res.statusCode, message);
  }

  @override
  String toString() => message;
}
