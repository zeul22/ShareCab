import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _map;

  // City-center fallback while we wait for the user's GPS fix.
  // Bengaluru (HSR Layout area) — primary launch city.
  static const LatLng _fallbackCenter = LatLng(12.9148106, 77.6764023);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loc = await context.read<LocationService>().fetchCurrent();
      if (loc != null && _map != null) {
        await _map!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(loc.lat, loc.lng), 15),
        );
      }
    });
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  void _startStandardFlow() {
    context.read<RideFlowState>().resetForNewSearch();
    Navigator.of(context).pushNamed(Routes.planRide);
  }

  void _startAirportFlow() {
    context.read<RideFlowState>().resetForNewSearch();
    Navigator.of(context).pushNamed(Routes.airportArrival);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final loc = context.watch<LocationService>();
    final flow = context.watch<RideFlowState>();

    // True whenever there's something the rider should be aware of and able
    // to jump back into. Covers active dispatched rides AND in-flight
    // searches (proposals.isNotEmpty during searching/proposing stages).
    final hasInFlightTrip = flow.activeRide != null ||
        (flow.proposals.isNotEmpty &&
            (flow.stage == FlowStage.searching ||
                flow.stage == FlowStage.proposing));

    final initial = loc.current != null
        ? LatLng(loc.current!.lat, loc.current!.lng)
        : _fallbackCenter;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: initial, zoom: 15),
              onMapCreated: (c) => _map = c,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.person_outline,
                    onTap: () => Navigator.of(context).pushNamed(Routes.profile),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: Icons.history,
                    onTap: () => Navigator.of(context).pushNamed(Routes.history),
                  ),
                  const SizedBox(width: 8),
                  _CircleButton(
                    icon: Icons.shield_outlined,
                    onTap: () => Navigator.of(context).pushNamed(Routes.helpSafety),
                  ),
                ],
              ),
            ),

            DraggableScrollableSheet(
              initialChildSize: 0.46,
              minChildSize: 0.32,
              maxChildSize: 0.85,
              builder: (context, scroll) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
                ),
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Hi ${auth.user?.name ?? 'there'} 👋',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Where are you headed?',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),

                    if (hasInFlightTrip)
                      _ActiveTripCard(flow: flow)
                    else ...[
                      _BigAction(
                        icon: Icons.search,
                        title: 'Book a shared ride',
                        subtitle: 'Pick a destination and we’ll find a co-rider going your way.',
                        onTap: _startStandardFlow,
                      ),
                      const SizedBox(height: 10),
                      _BigAction(
                        icon: Icons.flight_land,
                        title: 'Find match after landing',
                        subtitle: 'Travelling from the airport? Match with passengers landing at the same time.',
                        onTap: _startAirportFlow,
                        tone: _Tone.brand,
                      ),
                    ],

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.my_location, size: 18, color: AppTheme.brand),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            loc.current?.address ?? 'Detecting your location…',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.brandLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.eco_outlined, color: AppTheme.brandDark),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Share your ride with someone nearby and save up to 30%.',
                              style: TextStyle(color: AppTheme.brandDark, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: IconButton(icon: Icon(icon), onPressed: onTap),
    );
  }
}

/// Replaces the booking CTAs whenever the rider has an in-flight trip.
/// Routes them back to the right screen for the current stage rather than
/// letting them start a second trip (which the backend would 409 anyway).
class _ActiveTripCard extends StatelessWidget {
  final RideFlowState flow;
  const _ActiveTripCard({required this.flow});

  @override
  Widget build(BuildContext context) {
    // Pick the most-specific message + jump target for the current stage.
    final spec = _specFor(flow);
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(spec.targetRoute),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.brand,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(spec.icon, color: AppTheme.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ACTIVE RIDE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spec.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        spec.subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _ActiveTripSpec _specFor(RideFlowState flow) {
    final ride = flow.activeRide;

    // Post-accept (driver assigned / arriving / in_progress): take them to
    // RideConfirmation, which is also the natural place to access cancel.
    if (ride != null) {
      switch (flow.stage) {
        case FlowStage.inRide:
          return const _ActiveTripSpec(
            icon: Icons.directions_car,
            title: 'Ride in progress',
            subtitle: 'Tap to view your live ride',
            targetRoute: Routes.liveRide,
          );
        case FlowStage.paying:
          return const _ActiveTripSpec(
            icon: Icons.payments_outlined,
            title: 'Payment due',
            subtitle: 'Tap to settle your share',
            targetRoute: Routes.payment,
          );
        default:
          return const _ActiveTripSpec(
            icon: Icons.check_circle,
            title: 'Ride confirmed',
            subtitle: 'Tap to view OTP, driver & cancel option',
            targetRoute: Routes.rideConfirmation,
          );
      }
    }

    // Match found, awaiting confirm/reject.
    if (flow.stage == FlowStage.proposing) {
      return const _ActiveTripSpec(
        icon: Icons.handshake_outlined,
        title: 'Match found — confirm or reject',
        subtitle: 'Tap to review the proposal',
        targetRoute: Routes.matchResult,
      );
    }

    // Default = still searching.
    return const _ActiveTripSpec(
      icon: Icons.search,
      title: 'Looking for a co-rider',
      subtitle: 'Tap to view your search',
      targetRoute: Routes.searching,
    );
  }
}

class _ActiveTripSpec {
  final IconData icon;
  final String title;
  final String subtitle;
  final String targetRoute;
  const _ActiveTripSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.targetRoute,
  });
}

enum _Tone { neutral, brand }

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final _Tone tone;

  const _BigAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final isBrand = tone == _Tone.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isBrand ? AppTheme.brandLight : const Color(0xFFF4F6F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isBrand ? Colors.white : AppTheme.brandLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isBrand ? AppTheme.brandDark : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: isBrand ? AppTheme.brandDark : Colors.black38),
          ],
        ),
      ),
    );
  }
}
