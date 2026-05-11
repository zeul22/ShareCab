import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/api_config.dart';

/// Fetches a road-following polyline between two points (with optional
/// intermediate stops) from the Google Directions API.
///
/// Why this exists: drawing a `Polyline` directly between origin and
/// destination LatLngs renders the great-circle straight line — which is
/// what the rider sees overlaid on the map. To follow real roads we have
/// to ask Directions, which returns an encoded polyline that hugs the
/// actual route. `flutter_polyline_points` decodes that into LatLngs.
///
/// We don't need a client-side path-finder (Dijkstra/A*) — that would
/// require shipping the road graph, which is megabytes per city.
/// Google's API is the standard answer for mapping apps.
class RouteService {
  RouteService._();
  static final RouteService instance = RouteService._();

  final PolylinePoints _client = PolylinePoints();

  /// Cache by ordered-stops fingerprint. Identical requests within one
  /// session don't re-hit the API. We keep this in memory only — TTL is
  /// the app process lifetime, which matches the freshness window of a
  /// route (an hour or two at most).
  final Map<String, List<LatLng>> _cache = {};

  /// Fetch a road-following polyline through [stops]. Returns the input
  /// stops verbatim (i.e. straight-line fallback) when:
  ///   - fewer than 2 stops are provided
  ///   - the Google Maps API key isn't configured
  ///   - the Directions API call fails or returns no points
  ///
  /// Falling back rather than throwing means the map always has *something*
  /// drawn — a wrong-but-readable line is better than a missing one.
  Future<List<LatLng>> routeThrough(List<LatLng> stops) async {
    if (stops.length < 2) return stops;

    const key = ApiConfig.googleMapsKey;
    if (key.isEmpty) return stops;

    final fingerprint = _fingerprint(stops);
    final cached = _cache[fingerprint];
    if (cached != null) return cached;

    final origin = PointLatLng(stops.first.latitude, stops.first.longitude);
    final destination = PointLatLng(stops.last.latitude, stops.last.longitude);
    // Everything between origin and destination becomes a waypoint. The
    // Directions API supports up to 25 waypoints — well above what a 3-
    // rider shared cab will ever need.
    final waypoints = stops.length <= 2
        ? const <PolylineWayPoint>[]
        : [
            for (var i = 1; i < stops.length - 1; i++)
              PolylineWayPoint(
                location: '${stops[i].latitude},${stops[i].longitude}',
                stopOver: true,
              ),
          ];

    try {
      final result = await _client.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: origin,
          destination: destination,
          mode: TravelMode.driving,
          wayPoints: waypoints,
        ),
        googleApiKey: key,
      );

      // status is "OK" when Google returned a real route. Anything else
      // (REQUEST_DENIED, ZERO_RESULTS, OVER_QUERY_LIMIT) → straight line.
      // Surface the failure to debugPrint so a flat dashed route on the
      // ride screen isn't a silent mystery — the most common cause is
      // "Directions API not enabled" on the Google Cloud project.
      if (result.status != 'OK' || result.points.isEmpty) {
        debugPrint(
          '[routes] Directions returned status=${result.status} '
          'msg="${result.errorMessage ?? ''}" — falling back to straight line. '
          'Enable the Directions API for your Google Cloud project key.',
        );
        return stops;
      }

      final decoded = result.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(growable: false);
      _cache[fingerprint] = decoded;
      return decoded;
    } catch (e) {
      // Network or parser error — never block rendering, fall back.
      debugPrint('[routes] Directions request threw: $e — straight line.');
      return stops;
    }
  }

  /// Stable cache key. Rounds to 5 decimals (~1m precision) so trivial
  /// jitter in coordinate floats doesn't bust the cache.
  String _fingerprint(List<LatLng> stops) {
    return stops
        .map((p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join('|');
  }
}
