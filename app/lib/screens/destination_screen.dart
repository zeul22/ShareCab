import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/place.dart';
import '../models/recent_destination.dart';
import '../routes.dart';
import '../services/api/ride_api.dart';
import '../services/location_service.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';
import '../utils/trip_constraints.dart';
import 'map_picker_screen.dart';

/// Step 1 of the booking flow: pick a pickup and a drop. Continues to the
/// luggage step. The [RideFlowState] holds the selections so navigating back
/// keeps them.
///
/// Surfaces a "Recent destinations" shortcut row above the map picker —
/// tap a chip → drop is set + screen continues to the luggage step.
/// Stateful only because the recents need a one-shot fetch on init.
class DestinationScreen extends StatefulWidget {
  const DestinationScreen({super.key});

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  List<RecentDestination>? _recents;
  bool _recentsLoading = true;

  @override
  void initState() {
    super.initState();
    // Defer to the first frame so context.read works.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecents());
  }

  Future<void> _loadRecents() async {
    try {
      final list = await context.read<RideApi>().getRecentDestinations();
      if (!mounted) return;
      setState(() {
        _recents = list;
        _recentsLoading = false;
      });
    } catch (_) {
      // Soft-fail: a recents fetch shouldn't block the screen. Empty
      // state hides the section so the rider can still use the map
      // picker as usual.
      if (!mounted) return;
      setState(() {
        _recents = const [];
        _recentsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    final pickup = flow.search.pickup ?? context.read<LocationService>().current;
    final dropoff = flow.search.dropoff;
    final airport = flow.search.airportArrivalMode;
    // Instant client-side mirror of the backend's pickup↔drop distance
    // guard. Lets us disable Continue and surface a friendly error
    // BEFORE the round-trip to /trips. Backend is still the authority.
    final tripError = TripConstraints.validate(pickup, dropoff);

    Future<void> pick({required bool isPickup}) async {
      // Capture before the await so the analyzer is happy about the
      // BuildContext-across-async-gap warning — the State is also
      // gated by `mounted` below.
      final rideFlow = context.read<RideFlowState>();
      final picked = await Navigator.of(context).push<Place>(
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(
            title: isPickup ? 'Pickup' : 'Destination',
            initial: isPickup ? pickup : dropoff,
          ),
        ),
      );
      if (picked == null || !mounted) return;
      if (isPickup) {
        rideFlow.setPickup(picked);
      } else {
        rideFlow.setDropoff(picked);
      }
    }

    /// Tap a recent → set as drop, advance to luggage step. Skipping the
    /// map picker is the whole point of this shortcut.
    void useRecent(RecentDestination r) {
      context.read<RideFlowState>().setDropoff(r.toPlace());
      Navigator.of(context).pushNamed(Routes.luggage);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Plan your ride')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (airport)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.flight_land, color: AppTheme.brandDark, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Airport mode is on — we’ll match you with passengers landing in your window.',
                          style: TextStyle(color: AppTheme.brandDark, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              _PointTile(
                label: 'Pickup',
                place: pickup,
                emptyHint: 'Tap to set pickup',
                dotColor: AppTheme.brand,
                onTap: () => pick(isPickup: true),
              ),
              const SizedBox(height: 12),
              _PointTile(
                label: 'Destination',
                place: dropoff,
                emptyHint: 'Tap to set destination',
                dotColor: Colors.black87,
                onTap: () => pick(isPickup: false),
              ),
              if (tripError != null) ...[
                const SizedBox(height: 12),
                _TripErrorBanner(message: tripError),
              ],
              // Recents shortcut — only renders once fetched + non-empty.
              // First-time riders never see this section, so we don't
              // burn screen real estate on an empty state.
              if (!_recentsLoading && _recents != null && _recents!.isNotEmpty) ...[
                const SizedBox(height: 24),
                _RecentDestinationsSection(
                  recents: _recents!,
                  onTap: useRecent,
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: pickup != null && dropoff != null && tripError == null
                    ? () => Navigator.of(context).pushNamed(Routes.luggage)
                    : null,
                child: const Text('Next: luggage'),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can change pickup or destination any time before you accept a match.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recent destinations" shortcut. Each row is a tap-target that sets
/// the dropoff and advances the flow straight to the luggage step —
/// no map picker needed. Repeat trips ("home", "office") collapse
/// server-side so the list stays short.
class _RecentDestinationsSection extends StatelessWidget {
  final List<RecentDestination> recents;
  final ValueChanged<RecentDestination> onTap;
  const _RecentDestinationsSection({
    required this.recents,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Recent destinations',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Colors.black54,
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < recents.length; i++) ...[
          _RecentRow(recent: recents[i], onTap: () => onTap(recents[i])),
          if (i < recents.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  final RecentDestination recent;
  final VoidCallback onTap;
  const _RecentRow({required this.recent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final address = recent.address.isNotEmpty
        ? recent.address
        : '${recent.lat.toStringAsFixed(4)}, ${recent.lng.toStringAsFixed(4)}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history,
                  size: 18,
                  color: AppTheme.brandDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (recent.tripCount > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${recent.tripCount} trips',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline error chip shown below the destination tile when the chosen
/// pickup ↔ drop pair fails [TripConstraints.validate]. Same content
/// the backend would return on submit — we just surface it earlier so
/// the user fixes it without a round-trip + spinner.
class _TripErrorBanner extends StatelessWidget {
  final String message;
  const _TripErrorBanner({required this.message});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB00020), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB00020),
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

class _PointTile extends StatelessWidget {
  final String label;
  final Place? place;
  final String emptyHint;
  final Color dotColor;
  final VoidCallback onTap;

  const _PointTile({
    required this.label,
    required this.place,
    required this.emptyHint,
    required this.dotColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = place;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p?.address.isNotEmpty == true ? p!.address : emptyHint,
                    style: TextStyle(
                      fontSize: 15,
                      color: p == null ? Colors.black45 : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
