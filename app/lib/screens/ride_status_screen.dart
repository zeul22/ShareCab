import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../models/route_stop.dart';
import '../routes.dart';
import '../services/ride_flow.dart';
import '../services/route_service.dart';
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

  // Road-following polyline from Directions API. Null until fetched; we
  // render the straight-line stop sequence in the meantime so the rider
  // always has a route drawn. [_lastFingerprint] dedupes fetches when
  // build re-runs on every poll tick from RideFlowState.
  List<LatLng>? _roadPoints;
  String? _lastFingerprint;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _fetchRoute(List<LatLng> stops) async {
    if (stops.length < 2) return;
    final fp = stops
        .map((p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join('|');
    if (fp == _lastFingerprint) return;
    _lastFingerprint = fp;
    final road = await RouteService.instance.routeThrough(stops);
    if (!mounted) return;
    setState(() => _roadPoints = road);
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
    final flow = context.watch<RideFlowState>();
    final ride = flow.activeRide;
    if (ride == null) {
      return const Scaffold(body: Center(child: Text('No active ride.')));
    }

    // Polling watcher just told us the rider is now solo. Pop a dialog
    // letting them either continue at the higher solo fare or bail out
    // and search for another co-rider. Same flag/clear pattern as
    // RideConfirmationScreen — clear before showing so a quick rebuild
    // doesn't re-trigger.
    if (flow.coRiderLostPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<RideFlowState>().clearCoRiderLost();
        _showCoRiderLostDialog(ride.perRiderFare);
      });
    }

    // Driver pressed "Reached drop" on their side → backend flips this
    // rider's trip to completed → polling watcher syncs the local state.
    // We then auto-advance to payment so the rider doesn't have to press
    // a button at the end (the old "I've reached" button is gone).
    if (ride.status == RideStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Use pushReplacement so the back button doesn't bounce the
        // rider back into a completed ride view.
        Navigator.of(context).pushReplacementNamed(Routes.payment);
      });
    }

    final stopPoints = ride.proposal.stops
        .map((s) => LatLng(s.place.lat, s.place.lng))
        .toList(growable: false);

    // Kick off (or reuse) the Directions fetch. Deferred to a post-frame
    // callback so we don't call setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchRoute(stopPoints);
    });

    // Polyline rendering uses road-following points when available, else
    // falls back to the straight-line stop sequence so there's always a
    // route on the map.
    final polylinePoints = _roadPoints ?? stopPoints;

    return Scaffold(
      appBar: AppBar(title: const Text('Your ride')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: stopPoints.first, zoom: 13),
                onMapCreated: (c) {
                  _map = c;
                  // Fit bounds on the actual rendered polyline so the
                  // road bends are visible, not just the stop endpoints.
                  _fitBounds(polylinePoints);
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _markers(ride),
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: polylinePoints,
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

  /// Co-rider cancelled mid-ride. Decision is firmer here than on
  /// RideConfirmationScreen because the driver is already en route /
  /// driving — "wait for another" requires bailing out of the live ride
  /// entirely, which is a bigger commitment.
  Future<void> _showCoRiderLostDialog(double soloFare) async {
    final waitForAnother = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: const Text('Your co-rider cancelled'),
        content: Text(
          "You're the only rider now. Continue this ride solo at "
          '₹${soloFare.toStringAsFixed(0)} (the full fare), or cancel and search '
          'for a fresh co-rider? Cancelling now may incur a fee since the '
          'driver is already on the way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Continue solo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Cancel & re-search'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final flow = context.read<RideFlowState>();
    if (waitForAnother == true) {
      await flow.searchForAnother();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(Routes.searching);
    } else {
      flow.continueSolo();
    }
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
          // Driver-pushed completion: the driver presses "Reached drop"
          // on their end; we sync via polling and auto-advance the rider
          // to payment. So no "I've reached" button here — just a status
          // chip telling the rider what to expect, plus SOS.
          _DriverProgressChip(status: ride.status),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {/* SOS hook */},
              icon: const Icon(Icons.shield_outlined),
              label: const Text('SOS'),
            ),
          ),
          // Cancel still available mid-ride. Disable once the ride is in
          // an irreversible state (completed / cancelled).
          if (ride.status != RideStatus.completed &&
              ride.status != RideStatus.cancelled) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                onPressed: () => _confirmCancel(context),
                child: const Text('Cancel ride'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'Your driver and any co-riders will be notified. '
          'Cancellation fees may apply once the driver is en route.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await context.read<RideFlowState>().cancelActiveRide();
    if (!context.mounted) return;
    Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
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

/// Replaces the old "I've reached" button. Surfaces what the driver is
/// currently doing so the rider knows the trip will auto-advance to
/// payment as soon as the driver presses "Reached drop" on their side.
class _DriverProgressChip extends StatelessWidget {
  final RideStatus status;
  const _DriverProgressChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (text, icon) = switch (status) {
      RideStatus.confirmed => (
          'Driver is on the way to your pickup',
          Icons.directions_car_outlined,
        ),
      RideStatus.arriving => (
          'Driver is arriving — please be ready',
          Icons.directions_run,
        ),
      RideStatus.inProgress => (
          'On your way — driver will mark you dropped on arrival',
          Icons.navigation_outlined,
        ),
      RideStatus.completed => (
          'Trip complete · taking you to payment',
          Icons.check_circle_outline,
        ),
      RideStatus.cancelled => (
          'Ride cancelled',
          Icons.cancel_outlined,
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.brandDark, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.brandDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
