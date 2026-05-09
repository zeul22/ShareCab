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
  // The "new" Places API doesn't include reverse geocoding, so we use the
  // legacy Geocoding API. Same key, different host. Requires the **Geocoding
  // API** to be enabled on the GCP project that owns the key.
  static const _geocodeUrl = 'https://maps.googleapis.com/maps/api/geocode/json';

  /// Field mask tells Google which fields to include in the response. Smaller
  /// masks = lower per-request cost.
  static const _detailsFieldMask =
      'id,formattedAddress,location,displayName';

  bool get isConfigured => apiKey.isNotEmpty;

  Future<List<PlacePrediction>> autocomplete(String query) async {
    if (!isConfigured) {
      throw const _PlacesException(
        0,
        'Maps API key not configured. Build with --dart-define=GOOGLE_MAPS_KEY=AIza...',
      );
    }
    final input = query.trim();
    if (input.isEmpty) return const [];

    final res = await _client.post(
      Uri.parse(_autocompleteUrl),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
      },
      body: jsonEncode({
        'input': input,
        // ShareCab is India-only; restrict suggestions to Indian places so a
        // search like "Bangalore" doesn't surface "Bangalore, MA, USA".
        'includedRegionCodes': ['in'],
      }),
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
    if (placeId.isEmpty) return null;
    if (!isConfigured) {
      throw const _PlacesException(
        0,
        'Maps API key not configured. Build with --dart-define=GOOGLE_MAPS_KEY=AIza...',
      );
    }

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

  /// Reverse-geocode a coordinate into a human-readable formatted address.
  /// Returns null if the API key isn't configured, the request fails, or
  /// Google has no result for that point (e.g. middle of the ocean).
  ///
  /// Used by the map picker so dragging the pin shows a real address instead
  /// of the literal placeholder string "Pinned location".
  Future<String?> reverseGeocode(double lat, double lng) async {
    if (!isConfigured) return null;
    final uri = Uri.parse(_geocodeUrl).replace(queryParameters: {
      'latlng': '$lat,$lng',
      'key': apiKey,
      // ShareCab is India-only; bias results to localised Indian addresses.
      'region': 'in',
      'language': 'en',
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') return null;
    final results = body['results'] as List?;
    if (results == null || results.isEmpty) return null;
    return (results.first as Map<String, dynamic>)['formatted_address'] as String?;
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
