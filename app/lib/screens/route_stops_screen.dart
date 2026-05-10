import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/match_proposal.dart';
import '../models/route_stop.dart';
import '../services/route_service.dart';
import '../theme/app_theme.dart';

/// Detailed view of the stop sequence for a proposal. Reached from the
/// match-result card; takes a [MatchProposal] as `arguments`.
///
/// Layout: a Google Map at the top with a marker per stop and a polyline
/// connecting them in pickup→pickup→drop→drop order, then the existing
/// timeline list below for textual context.
class RouteStopsScreen extends StatefulWidget {
  const RouteStopsScreen({super.key});

  @override
  State<RouteStopsScreen> createState() => _RouteStopsScreenState();
}

class _RouteStopsScreenState extends State<RouteStopsScreen> {
  GoogleMapController? _map;
  MatchProposal? _proposal;

  // Road-following polyline from Directions API. Null until fetched —
  // we render the straight-line stop sequence as a placeholder so the
  // map always has a route drawn while the API call is in flight.
  List<LatLng>? _roadPoints;
  bool _routeRequested = false;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _fetchRoute(MatchProposal proposal) async {
    if (_routeRequested) return;
    _routeRequested = true;
    final stops = proposal.stops
        .map((s) => LatLng(s.place.lat, s.place.lng))
        .toList(growable: false);
    if (stops.length < 2) return;
    final road = await RouteService.instance.routeThrough(stops);
    if (!mounted) return;
    setState(() => _roadPoints = road);
  }

  /// Auto-fit the camera to show every stop with a comfortable margin.
  /// Called once the map is ready.
  void _fitToStops(MatchProposal proposal) {
    final controller = _map;
    if (controller == null || proposal.stops.isEmpty) return;

    final points = proposal.stops
        .map((s) => LatLng(s.place.lat, s.place.lng))
        .toList(growable: false);

    if (points.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        // 60px padding so markers aren't clipped at the edges.
        60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _proposal ??= ModalRoute.of(context)!.settings.arguments as MatchProposal;
    final proposal = _proposal!;

    // Kick off the Directions fetch once per screen lifetime. Deferred to
    // a post-frame callback so we don't setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchRoute(proposal);
    });

    final markers = <Marker>{
      for (var i = 0; i < proposal.stops.length; i++)
        _markerForStop(proposal.stops[i], i),
    };

    final stopPoints = [
      for (final s in proposal.stops) LatLng(s.place.lat, s.place.lng),
    ];
    // Use road-following points when the Directions call has returned;
    // otherwise show the straight-line placeholder so the map's never
    // empty while the network call is in flight.
    final polylinePoints = _roadPoints ?? stopPoints;

    final polylines = proposal.stops.length < 2
        ? const <Polyline>{}
        : <Polyline>{
            Polyline(
              polylineId: const PolylineId('route'),
              points: polylinePoints,
              color: AppTheme.brand,
              width: 4,
              // Solid once we have a real road route; dashed while we're
              // still showing the straight-line placeholder, so the user
              // can tell at a glance whether it's a rough sequence or
              // the actual driving path.
              patterns: _roadPoints != null
                  ? const []
                  : [PatternItem.dash(20), PatternItem.gap(8)],
            ),
          };

    final initialTarget = proposal.stops.isNotEmpty
        ? LatLng(proposal.stops.first.place.lat, proposal.stops.first.place.lng)
        : const LatLng(12.9716, 77.5946); // Bengaluru fallback

    return Scaffold(
      appBar: AppBar(title: const Text('Route & stops')),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 280,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: initialTarget, zoom: 13),
                onMapCreated: (c) {
                  _map = c;
                  _fitToStops(proposal);
                },
                markers: markers,
                polylines: polylines,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                liteModeEnabled: false,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${proposal.stops.length} stops · ${proposal.distanceKm.toStringAsFixed(1)} km · ${proposal.durationMin} min',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(proposal.stops.length, (i) {
                    final s = proposal.stops[i];
                    final isLast = i == proposal.stops.length - 1;
                    return _StopTile(stop: s, isLast: isLast, index: i);
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _markerForStop(RouteStop stop, int index) {
    final isPickup = stop.kind == StopKind.pickup;
    return Marker(
      markerId: MarkerId('stop_$index'),
      position: LatLng(stop.place.lat, stop.place.lng),
      // Brand-aligned hueAzure for pickups, hueRed for dropoffs — clear visual
      // contrast even for users glancing at the map without reading labels.
      icon: BitmapDescriptor.defaultMarkerWithHue(
        isPickup ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed,
      ),
      infoWindow: InfoWindow(
        title: '${index + 1}. ${isPickup ? "Pickup" : "Drop"} · ${stop.passengerFirstName}',
        snippet: stop.place.address.isEmpty
            ? '${stop.place.lat.toStringAsFixed(4)}, ${stop.place.lng.toStringAsFixed(4)}'
            : stop.place.address,
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final RouteStop stop;
  final bool isLast;
  // 0-based index in the route, surfaced as "1." / "2." labels so the list
  // lines up with the numbered InfoWindow titles on the map.
  final int index;
  const _StopTile({
    required this.stop,
    required this.isLast,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.kind == StopKind.pickup;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isPickup ? AppTheme.brand : Colors.black87,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.black12),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isPickup ? 'Pickup · ${stop.passengerFirstName}' : 'Drop · ${stop.passengerFirstName}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '+${stop.etaFromStartMin} min',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.place.address.isEmpty ? '${stop.place.lat.toStringAsFixed(4)}, ${stop.place.lng.toStringAsFixed(4)}' : stop.place.address,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
