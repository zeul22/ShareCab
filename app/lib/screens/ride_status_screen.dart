import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/driver_live_location.dart';
import '../models/ride.dart';
import '../models/route_stop.dart';
import '../routes.dart';
import '../services/api/ride_api.dart';
import '../services/ride_flow.dart';
import '../services/route_service.dart';
import '../services/trip_tracking_service.dart';
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

  /// The trip id the tracker is currently watching. Tracked locally so
  /// we restart the poll if the ride id changes mid-screen (e.g. the
  /// user returned from completed → new ride without the screen unmounting).
  String? _trackedTripId;

  @override
  void dispose() {
    _map?.dispose();
    // Stop the tracker so it doesn't keep polling after the user leaves
    // this screen. Idempotent — safe even if start() was never called.
    context.read<TripTrackingService>().stop();
    super.dispose();
  }

  void _ensureTracking(String tripId) {
    if (_trackedTripId == tripId) return;
    _trackedTripId = tripId;
    // Defer to a post-frame callback so we don't trigger notifyListeners
    // (from inside start()) during a build pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TripTrackingService>().start(tripId);
    });
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

    // Start (or re-target) the live tracker for this ride. Idempotent;
    // a no-op when already tracking the same id.
    _ensureTracking(ride.id);

    // Listen on the tracker so the driver marker + ETA chip re-render
    // on each 5s tick. Watching here (not in dispose / lifecycle) keeps
    // the dependency explicit + scoped to the build.
    final tracker = context.watch<TripTrackingService>();

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
            // Live ETA chip — "Driver 4 min away" / "Reaching destination
            // in 12 min". Self-hides when the tracker has nothing to say
            // (no driver assigned yet, or non-active states).
            _EtaChip(eta: tracker.eta),
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
                markers: _markers(ride, tracker.driverLocation),
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: polylinePoints,
                    color: AppTheme.brand,
                    width: 4,
                    // Solid when Directions API gave us real road
                    // geometry; dashed while we're still showing the
                    // straight-line fallback. The rider can tell at a
                    // glance whether the path is approximate or real.
                    patterns: _roadPoints != null
                        ? const []
                        : [PatternItem.dash(20), PatternItem.gap(10)],
                  ),
                },
              ),
            ),
            _RideCard(ride: ride),
            // Rider-initiated end. Only meaningful once the ride is
            // actually underway — pre-pickup, /cancel is the right tool
            // (no charge). Mid-ride, /end-early stops the cab here and
            // charges the full pre-quoted fare.
            if (ride.status == RideStatus.inProgress)
              _EndRideButton(ride: ride),
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

  Set<Marker> _markers(Ride ride, DriverLiveLocation? driverPos) {
    final markers = <Marker>{};

    // Snap "my pickup" marker to the actual GPS the driver captured
    // once we've transitioned to in_progress. Before that, show the
    // requested pickup pin (where the rider tapped at booking time).
    // Co-rider stops stick to their original requested coords — actuals
    // for other riders aren't surfaced to this rider.
    final useActualPickup =
        ride.status == RideStatus.inProgress && ride.actualPickup != null;

    for (final s in ride.proposal.stops) {
      final isMine = s.passengerId == 'me';
      final pos = (isMine && s.kind == StopKind.pickup && useActualPickup)
          ? LatLng(ride.actualPickup!.lat, ride.actualPickup!.lng)
          : LatLng(s.place.lat, s.place.lng);
      markers.add(
        Marker(
          markerId: MarkerId('${s.kind.name}_${s.passengerId}_${s.order}'),
          position: pos,
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

    // Driver cab marker. Only shown when the tracker has a position AND
    // the ride is in a state where the rider should be looking at it.
    final showDriver = driverPos != null &&
        (ride.status == RideStatus.arriving ||
            ride.status == RideStatus.inProgress);
    if (showDriver) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(driverPos.lat, driverPos.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Your driver'),
        ),
      );
    }
    return markers;
  }
}

/// Compact chip above the map that surfaces the live ETA from the
/// [TripTrackingService]. Hidden when the trip isn't actively heading
/// somewhere (e.g. matched but no driver yet).
class _EtaChip extends StatelessWidget {
  final TripEta? eta;
  const _EtaChip({required this.eta});

  @override
  Widget build(BuildContext context) {
    final e = eta;
    if (e == null) return const SizedBox.shrink();
    final mins = e.minutes;
    final label = e.isToPickup
        ? (mins <= 1 ? 'Driver almost here' : 'Driver $mins min away')
        : (mins <= 1 ? 'Arriving now' : 'Reaching destination in $mins min');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.brand,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            e.isToPickup ? Icons.directions_car : Icons.flag_outlined,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (e.isApproximate) ...[
            const SizedBox(width: 6),
            const Text(
              '(approx)',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// "End ride here" — rider-initiated early end while in_progress.
/// Confirmation dialog is non-skippable so the rider can't fat-thumb
/// past the "full fare, no refund" notice. On confirm, hits
/// /trips/:id/end-early, then auto-advances to the payment screen the
/// next time the polling watcher sees status=completed.
class _EndRideButton extends StatefulWidget {
  final Ride ride;
  const _EndRideButton({required this.ride});

  @override
  State<_EndRideButton> createState() => _EndRideButtonState();
}

class _EndRideButtonState extends State<_EndRideButton> {
  bool _busy = false;

  Future<void> _confirm() async {
    final fare = widget.ride.perRiderFare;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: const Text('End the ride here?'),
        content: Text(
          'You\'ll be charged the full fare of ₹${fare.toStringAsFixed(0)} '
          '— no refund for the part you didn\'t ride. The driver continues '
          'with any co-riders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Keep riding'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('End ride'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final api = context.read<RideApi>();
    setState(() => _busy = true);
    try {
      await api.endRideEarly(widget.ride.id);
      // Don't navigate here — the polling watcher in RideFlowState picks
      // up the status=completed flip on its next tick and the screen's
      // existing "completed → push payment" branch (in build) fires.
      // Reduces flow paths to maintain.
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _confirm,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.stop_circle_outlined, color: Colors.red),
        label: Text(
          _busy ? 'Ending ride…' : 'End ride here',
          style: TextStyle(
            color: _busy ? Colors.black54 : Colors.red.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.red.shade300),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
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
          // Hide the "Driver ... · plate ..." line in rider-only mode,
          // where the backend doesn't assign a driver — otherwise we'd
          // render placeholder text ("Driver Awaiting driver · plate ··")
          // which is just visual noise.
          if (ride.driver.id.isNotEmpty)
            Text(
              'Driver ${ride.driver.name} · plate ••${ride.driver.vehicle.plateLast4}',
              style: const TextStyle(color: Colors.black54),
            )
          else
            const Text(
              'Coordinate the pickup spot via chat with your co-rider.',
              style: TextStyle(color: Colors.black54),
            ),
          const SizedBox(height: 16),
          // Driver-pushed completion: the driver presses "Reached drop"
          // on their end; we sync via polling and auto-advance the rider
          // to payment. So no "I've reached" button here — just a status
          // chip telling the rider what to expect, plus SOS.
          _DriverProgressChip(
            status: ride.status,
            riderOnly: ride.driver.id.isEmpty,
          ),
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
        return 'Looking for a driver';
      case RideStatus.driverAssigned:
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

/// Replaces the old "I've reached" button. Surfaces what's happening
/// in the ride so the rider knows what comes next without having to
/// poke around. Driver-dispatch copy ("Driver is on the way…") swaps
/// out for rider-only copy ("Coordinate with your co-rider…") when
/// there's no driver assigned.
class _DriverProgressChip extends StatelessWidget {
  final RideStatus status;
  final bool riderOnly;
  const _DriverProgressChip({
    required this.status,
    this.riderOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final (text, icon) = riderOnly
        ? _riderOnlyCopy(status)
        : _withDriverCopy(status);
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

  /// Copy variants for the driver-dispatch flow (existing default).
  static (String, IconData) _withDriverCopy(RideStatus status) {
    return switch (status) {
      RideStatus.confirmed => (
          'Looking for a driver',
          Icons.hourglass_top_outlined,
        ),
      RideStatus.driverAssigned => (
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
  }

  /// Copy variants for rider-only mode — no driver in the picture,
  /// the rider is coordinating their own cab with the co-rider via
  /// the in-app chat. Status enum still represents the trip lifecycle.
  static (String, IconData) _riderOnlyCopy(RideStatus status) {
    return switch (status) {
      RideStatus.confirmed || RideStatus.driverAssigned => (
          'Match locked in · open chat to coordinate your cab',
          Icons.chat_bubble_outline,
        ),
      RideStatus.arriving => (
          'Heading to pickup · chat with your co-rider',
          Icons.chat_bubble_outline,
        ),
      RideStatus.inProgress => (
          'Ride underway · stay in touch via chat',
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
  }
}
