import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/driver_dispatch.dart';
import '../services/api/driver_api.dart';
import '../services/route_service.dart';
import '../theme/app_theme.dart';

/// Driver's view of the trip(s) currently dispatched to them. Shows the
/// rider list (1-3 people), the optimal stop sequence, and per-rider
/// "Reached" CTAs so the driver confirms each pickup / drop individually
/// — much better than the rider having to press "I've reached".
///
/// The screen subscribes to the GPS stream and flags a banner at the top
/// the moment the driver enters [_geofenceMeters] of any pending stop.
/// That way they don't have to scroll through the stops list to find the
/// right "Reached" button — it's surfaced for them.
///
/// Polls `/drivers/me/dispatch` every 8s so a rider cancelling mid-trip
/// is reflected without a manual refresh. Cancels its timer on dispose.
class DriverActiveTripScreen extends StatefulWidget {
  const DriverActiveTripScreen({super.key});

  @override
  State<DriverActiveTripScreen> createState() => _DriverActiveTripScreenState();
}

class _DriverActiveTripScreenState extends State<DriverActiveTripScreen> {
  static const _pollInterval = Duration(seconds: 8);

  // Radius around a pending stop within which we treat the driver as
  // "arrived". 80m is generous enough to fire reliably even with the
  // ±10m GPS accuracy you typically get on a phone in a city, but tight
  // enough that it doesn't false-positive at adjacent stops.
  static const double _geofenceMeters = 80;

  DriverDispatch? _dispatch;
  bool _loading = true;
  String? _error;
  // Per-trip-id flags so the right CTA shows a spinner without locking
  // the whole screen — the driver might queue actions on multiple riders
  // (e.g. tap "Reached pickup" for rider A, then tap rider B before the
  // first response lands).
  final Set<String> _busyTripIds = {};

  Timer? _poll;
  GoogleMapController? _map;
  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  DriverApi get _api => context.read<DriverApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
      _startPositionStream();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _positionSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  /// Listen to the device GPS so we can show the geofence banner without
  /// manual refresh. We tolerate permission-denied silently — the screen
  /// still works, the geofence banner just never appears (driver falls
  /// back to picking the right rider from the list themselves).
  Future<void> _startPositionStream() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Update on every ~10m of movement — granular enough for the
          // 80m geofence, light enough to not drain battery.
          distanceFilter: 10,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() => _currentLatLng = LatLng(pos.latitude, pos.longitude));
      });
    } catch (_) {
      // Permission/location plugin error — ignore; we degrade gracefully.
    }
  }

  /// Reload the dispatch. `silent: true` suppresses the loading spinner
  /// (used by the timer tick) so the UI doesn't flash on every poll.
  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    try {
      final d = await _api.getMyDispatch();
      if (!mounted) return;
      setState(() {
        _dispatch = d;
        _loading = false;
        _error = null;
      });
      _maybePopOnCompletion(d);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  /// Bulk "I'm on the way" — called once before any pickup. Walks every
  /// sibling trip from `driver_assigned` to `arriving` in one shot. The
  /// per-rider lifecycle takes over from there.
  Future<void> _markOnTheWay() async {
    final d = _dispatch;
    final tripId = d?.primaryTripId;
    if (d == null || tripId == null) return;
    setState(() {
      _busyTripIds.add(tripId);
      _error = null;
    });
    try {
      final updated = await _api.arriveTrip(tripId);
      if (!mounted) return;
      setState(() {
        _dispatch = updated;
        _busyTripIds.remove(tripId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyTripIds.remove(tripId);
        _error = _clean(e);
      });
    }
  }

  /// Per-rider stop confirmation. The kind of action depends on the
  /// stop: pickup vs drop, dispatched to the right backend endpoint.
  Future<void> _markStopReached(DispatchStop stop) async {
    if (_busyTripIds.contains(stop.tripId)) return;
    setState(() {
      _busyTripIds.add(stop.tripId);
      _error = null;
    });
    try {
      final updated = stop.kind == DispatchStopKind.pickup
          ? await _api.markPickedUp(stop.tripId)
          : await _api.markDropped(stop.tripId);
      if (!mounted) return;
      setState(() {
        _dispatch = updated;
        _busyTripIds.remove(stop.tripId);
      });
      if (stop.kind == DispatchStopKind.dropoff && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${stop.riderName} dropped.'),
            duration: const Duration(seconds: 2),
          ));
      }
      _maybePopOnCompletion(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyTripIds.remove(stop.tripId);
        _error = _clean(e);
      });
    }
  }

  void _maybePopOnCompletion(DriverDispatch d) {
    // All riders dropped → trip done → bounce to home.
    if (d.allDropped && d.riders.isNotEmpty && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Closest pending stop within the geofence radius, or null if no
  /// stop is currently in range. The screen surfaces this as a top
  /// banner with the matching "Reached" CTA so the driver doesn't have
  /// to scroll through the stops list to find the right one.
  DispatchStop? _stopInGeofence() {
    final pos = _currentLatLng;
    final d = _dispatch;
    if (pos == null || d == null) return null;
    DispatchStop? best;
    double bestDist = _geofenceMeters;
    for (final s in d.pendingStops) {
      final m = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, s.place.lat, s.place.lng,
      );
      if (m <= bestDist) {
        best = s;
        bestDist = m;
      }
    }
    return best;
  }

  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  @override
  Widget build(BuildContext context) {
    final d = _dispatch;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active trip'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && d == null
            ? const Center(child: CircularProgressIndicator())
            : (d == null || d.isEmpty)
                ? const _EmptyState()
                : _DispatchView(
                    dispatch: d,
                    busyTripIds: _busyTripIds,
                    error: _error,
                    geofencedStop: _stopInGeofence(),
                    onMarkOnTheWay: _markOnTheWay,
                    onMarkStopReached: _markStopReached,
                    onMapCreated: (c) => _map = c,
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car_outlined, size: 56, color: Colors.black26),
            SizedBox(height: 12),
            Text(
              'No active dispatch',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'You\'ll be routed here automatically when a rider is matched to you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DispatchView extends StatelessWidget {
  final DriverDispatch dispatch;
  final Set<String> busyTripIds;
  final String? error;
  final DispatchStop? geofencedStop;
  final VoidCallback onMarkOnTheWay;
  final ValueChanged<DispatchStop> onMarkStopReached;
  final ValueChanged<GoogleMapController> onMapCreated;

  const _DispatchView({
    required this.dispatch,
    required this.busyTripIds,
    required this.error,
    required this.geofencedStop,
    required this.onMarkOnTheWay,
    required this.onMarkStopReached,
    required this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    final preArrival = dispatch.allAwaitingPickup;
    return Column(
      children: [
        // Geofence banner pinned to the top — surfaces the moment the
        // driver is within ~80m of any pending stop, with a one-tap
        // "Reached" button so they don't have to scan the stops list.
        if (geofencedStop != null)
          _GeofenceBanner(
            stop: geofencedStop!,
            busy: busyTripIds.contains(geofencedStop!.tripId),
            onConfirm: () => onMarkStopReached(geofencedStop!),
          ),
        SizedBox(
          height: 240,
          child: _RouteMap(dispatch: dispatch, onMapCreated: onMapCreated),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _StatusBanner(status: dispatch.status, isShared: dispatch.isShared),
              const SizedBox(height: 16),
              _RidersCard(dispatch: dispatch),
              const SizedBox(height: 16),
              // Pre-arrival the stops list is purely informational — the
              // driver hasn't started moving yet, so we don't show per-
              // stop "Reached" buttons. Once arriving, the stops card
              // becomes the action surface.
              _StopsCard(
                dispatch: dispatch,
                busyTripIds: busyTripIds,
                interactive: !preArrival,
                onReached: onMarkStopReached,
              ),
              const SizedBox(height: 16),
              _FareCard(dispatch: dispatch),
              if (error != null) ...[
                const SizedBox(height: 16),
                _ErrorChip(message: error!),
              ],
            ],
          ),
        ),
        // Bulk pre-arrival CTA only — once the driver is arriving, the
        // per-stop CTAs (in the stops card + the geofence banner) take
        // over, so we drop the bottom button.
        if (preArrival)
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: busyTripIds.contains(dispatch.primaryTripId)
                    ? null
                    : onMarkOnTheWay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brand,
                  foregroundColor: Colors.white,
                ),
                child: busyTripIds.contains(dispatch.primaryTripId)
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "I'm on the way",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _RouteMap extends StatefulWidget {
  final DriverDispatch dispatch;
  final ValueChanged<GoogleMapController> onMapCreated;
  const _RouteMap({required this.dispatch, required this.onMapCreated});

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  // Road-following points from the Directions API. Null until the first
  // fetch completes; we render the straight-line stops in the meantime so
  // the rider always sees *something*. Swapped in via setState once Google
  // returns the decoded polyline.
  List<LatLng>? _roadPoints;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  @override
  void didUpdateWidget(covariant _RouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-fetch if the stops actually changed (e.g. a co-rider was
    // dropped). Comparing by id+coords is cheaper than refetching every
    // poll tick — and Directions calls cost real money.
    if (!_stopsEqual(oldWidget.dispatch.stops, widget.dispatch.stops)) {
      setState(() => _roadPoints = null);
      _fetchRoute();
    }
  }

  Future<void> _fetchRoute() async {
    final stops = widget.dispatch.stops;
    if (stops.length < 2) return;
    final pts = stops.map((s) => LatLng(s.place.lat, s.place.lng)).toList();
    final road = await RouteService.instance.routeThrough(pts);
    if (!mounted) return;
    setState(() => _roadPoints = road);
  }

  bool _stopsEqual(List<DispatchStop> a, List<DispatchStop> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].tripId != b[i].tripId ||
          a[i].kind != b[i].kind ||
          a[i].place.lat != b[i].place.lat ||
          a[i].place.lng != b[i].place.lng) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.dispatch.stops;
    if (stops.isEmpty) {
      return Container(
        color: const Color(0xFFEFEFEF),
        alignment: Alignment.center,
        child: const Text('No route data', style: TextStyle(color: Colors.black54)),
      );
    }
    final markers = <Marker>{};
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final isPickup = s.kind == DispatchStopKind.pickup;
      markers.add(Marker(
        markerId: MarkerId('${s.kind.name}_${s.tripId}'),
        position: LatLng(s.place.lat, s.place.lng),
        infoWindow: InfoWindow(
          title: '${i + 1}. ${isPickup ? 'Pickup' : 'Drop'} · ${s.riderName}',
          snippet: s.place.address,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isPickup ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
        ),
      ));
    }
    final first = stops.first.place;
    final polylinePoints = _roadPoints ??
        [for (final s in stops) LatLng(s.place.lat, s.place.lng)];
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(first.lat, first.lng),
        zoom: 13,
      ),
      markers: markers,
      polylines: stops.length < 2
          ? const {}
          : {
              Polyline(
                polylineId: const PolylineId('route'),
                color: AppTheme.brand,
                width: 4,
                points: polylinePoints,
              ),
            },
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      onMapCreated: widget.onMapCreated,
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final DispatchStatus status;
  final bool isShared;
  const _StatusBanner({required this.status, required this.isShared});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      DispatchStatus.assigned => (Colors.amber.shade700, Icons.assignment_turned_in_outlined),
      DispatchStatus.arriving => (AppTheme.brand, Icons.directions_run),
      DispatchStatus.inProgress => (AppTheme.brand, Icons.directions_car),
      DispatchStatus.completed => (Colors.green.shade700, Icons.check_circle_outline),
      DispatchStatus.unknown => (Colors.black38, Icons.help_outline),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                Text(
                  isShared ? 'Shared cab' : 'Solo trip',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RidersCard extends StatelessWidget {
  final DriverDispatch dispatch;
  const _RidersCard({required this.dispatch});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              'RIDERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.black54,
              ),
            ),
          ),
          for (var i = 0; i < dispatch.riders.length; i++) ...[
            _RiderRow(rider: dispatch.riders[i]),
            if (i < dispatch.riders.length - 1)
              const Divider(height: 1, indent: 14, endIndent: 14),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _RiderRow extends StatelessWidget {
  final DispatchRider rider;
  const _RiderRow({required this.rider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.brandLight,
            child: Text(
              rider.firstName.isNotEmpty ? rider.firstName[0].toUpperCase() : '?',
              style: const TextStyle(color: AppTheme.brandDark, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rider.name.isNotEmpty ? rider.name : 'Rider',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, size: 13, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      rider.rating.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₹${rider.fareEstimate.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StopsCard extends StatelessWidget {
  final DriverDispatch dispatch;
  // Trip ids whose per-stop CTA should be disabled + spinning. Lets the
  // driver queue actions on multiple riders without locking the whole UI.
  final Set<String> busyTripIds;
  // Pre-arrival the stops list is informational (no "Reached" buttons).
  // Once arriving, every still-pending stop gets its own confirm CTA.
  final bool interactive;
  final ValueChanged<DispatchStop> onReached;

  const _StopsCard({
    required this.dispatch,
    required this.busyTripIds,
    required this.interactive,
    required this.onReached,
  });

  @override
  Widget build(BuildContext context) {
    final byTripId = {for (final r in dispatch.riders) r.tripId: r};
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              'ROUTE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.black54,
              ),
            ),
          ),
          for (var i = 0; i < dispatch.stops.length; i++)
            _StopRow(
              index: i + 1,
              stop: dispatch.stops[i],
              isLast: i == dispatch.stops.length - 1,
              done: _stopDone(dispatch.stops[i], byTripId),
              busy: busyTripIds.contains(dispatch.stops[i].tripId),
              interactive: interactive,
              onReached: () => onReached(dispatch.stops[i]),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // Mirror of `DriverDispatch._isPending` for individual stop rows: a
  // stop is "done" once the corresponding rider has progressed past it.
  static bool _stopDone(DispatchStop s, Map<String, DispatchRider> byTripId) {
    final r = byTripId[s.tripId];
    if (r == null) return false;
    if (s.kind == DispatchStopKind.pickup) return r.pickupDone;
    return r.dropDone;
  }
}

class _StopRow extends StatelessWidget {
  final int index;
  final DispatchStop stop;
  final bool isLast;
  final bool done;
  final bool busy;
  final bool interactive;
  final VoidCallback onReached;
  const _StopRow({
    required this.index,
    required this.stop,
    required this.isLast,
    required this.done,
    required this.busy,
    required this.interactive,
    required this.onReached,
  });

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.kind == DispatchStopKind.pickup;
    final color = done
        ? Colors.black38
        : (isPickup ? Colors.green.shade700 : Colors.red.shade700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '$index',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: Colors.black12,
                  margin: const EdgeInsets.only(top: 2),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isPickup ? 'Pickup' : 'Drop'} · ${stop.riderName}'
                    '${done ? ' · done' : ''}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.6,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.place.address.isNotEmpty
                        ? stop.place.address
                        : '${stop.place.lat.toStringAsFixed(4)}, ${stop.place.lng.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: done ? Colors.black45 : Colors.black87,
                    ),
                  ),
                  if (interactive && !done) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton(
                        onPressed: busy ? null : onReached,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                isPickup
                                    ? 'Reached pickup'
                                    : 'Reached drop',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Banner that pops at the top of the screen when the driver is within
/// [_DriverActiveTripScreenState._geofenceMeters] of a pending stop. The
/// "Confirm" button dispatches the same lifecycle endpoint as the per-
/// stop CTA in the stops list — this is just a more prominent surface
/// so the driver doesn't have to think about which rider they're at.
class _GeofenceBanner extends StatelessWidget {
  final DispatchStop stop;
  final bool busy;
  final VoidCallback onConfirm;
  const _GeofenceBanner({
    required this.stop,
    required this.busy,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.kind == DispatchStopKind.pickup;
    return Container(
      width: double.infinity,
      color: AppTheme.brand,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPickup
                      ? "You've reached ${stop.riderName}'s pickup"
                      : "You've reached ${stop.riderName}'s drop",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (stop.place.address.isNotEmpty)
                  Text(
                    stop.place.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: busy ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.brand,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.brand,
                    ),
                  )
                : Text(
                    isPickup ? 'Confirm pickup' : 'Confirm drop',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FareCard extends StatelessWidget {
  final DriverDispatch dispatch;
  const _FareCard({required this.dispatch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: AppTheme.brandDark),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Total fare to collect',
              style: TextStyle(color: AppTheme.brandDark, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '₹${dispatch.totalFare.toStringAsFixed(0)}',
            style: const TextStyle(
              color: AppTheme.brandDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ErrorChip extends StatelessWidget {
  final String message;
  const _ErrorChip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1C0C0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB00020), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
