import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../models/route_stop.dart';
import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Live ride status. After confirmation, the rider sits here while the cab
/// makes the rounds. Riders trigger "I've reached" to end the trip and move
/// to payment. Real backends would push status via socket; this scaffold
/// uses a manual button for the demo.
class RideStatusScreen extends StatefulWidget {
  const RideStatusScreen({super.key});

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> {
  GoogleMapController? _map;
  bool _fittedOnce = false;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _fitBounds(List<LatLng> points) async {
    if (_map == null || _fittedOnce || points.isEmpty) return;
    _fittedOnce = true;
    var sw = points.first;
    var ne = points.first;
    for (final p in points) {
      sw = LatLng(
        p.latitude < sw.latitude ? p.latitude : sw.latitude,
        p.longitude < sw.longitude ? p.longitude : sw.longitude,
      );
      ne = LatLng(
        p.latitude > ne.latitude ? p.latitude : ne.latitude,
        p.longitude > ne.longitude ? p.longitude : ne.longitude,
      );
    }
    await _map!.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.watch<RideFlowState>().activeRide;
    if (ride == null) {
      return const Scaffold(body: Center(child: Text('No active ride.')));
    }

    final points = ride.proposal.stops
        .map((s) => LatLng(s.place.lat, s.place.lng))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Your ride')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: points.first, zoom: 13),
                onMapCreated: (c) {
                  _map = c;
                  _fitBounds(points);
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _markers(ride),
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: points,
                    color: AppTheme.brand,
                    width: 4,
                    patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                  ),
                },
              ),
            ),
            _RideCard(ride: ride),
          ],
        ),
      ),
    );
  }

  Set<Marker> _markers(Ride ride) {
    final markers = <Marker>{};
    for (final s in ride.proposal.stops) {
      markers.add(
        Marker(
          markerId: MarkerId('${s.kind.name}_${s.passengerId}_${s.order}'),
          position: LatLng(s.place.lat, s.place.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            s.kind == StopKind.pickup
                ? BitmapDescriptor.hueOrange
                : BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: s.kind == StopKind.pickup
                ? 'Pickup · ${s.passengerFirstName}'
                : 'Drop · ${s.passengerFirstName}',
          ),
        ),
      );
    }
    return markers;
  }
}

class _RideCard extends StatelessWidget {
  final Ride ride;
  const _RideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 14)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _humanStatus(ride.status),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${ride.proposal.riderCount} riders · ${ride.proposal.vehicleType.name}',
                  style: const TextStyle(
                    color: AppTheme.brandDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Driver ${ride.driver.name} · plate ••${ride.driver.vehicle.plateLast4}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {/* SOS hook */},
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('SOS'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await context.read<RideFlowState>().markRideComplete();
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacementNamed(Routes.payment);
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('I’ve reached'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _humanStatus(RideStatus s) {
    switch (s) {
      case RideStatus.confirmed:
        return 'Driver on the way';
      case RideStatus.arriving:
        return 'Driver arriving';
      case RideStatus.inProgress:
        return 'On the way';
      case RideStatus.completed:
        return 'Completed';
      case RideStatus.cancelled:
        return 'Cancelled';
    }
  }
}
