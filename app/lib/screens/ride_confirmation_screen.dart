import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../models/vehicle.dart';
import '../routes.dart';
import '../services/api/ride_api.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';
import '../widgets/fare_breakdown_card.dart';

/// Driver + car + OTP screen. The OTP is shown only after the user reaches
/// this point (i.e. the ride is confirmed).
///
/// Polls the active ride via [RideFlowState] so a co-rider's late cancellation
/// updates this screen automatically (rider count + per-rider fare).
class RideConfirmationScreen extends StatefulWidget {
  const RideConfirmationScreen({super.key});

  @override
  State<RideConfirmationScreen> createState() => _RideConfirmationScreenState();
}

class _RideConfirmationScreenState extends State<RideConfirmationScreen> {
  // Cache the flow so dispose() doesn't have to look it up via context — at
  // unmount time the InheritedWidget lookup throws (the element is no longer
  // in the active tree). didChangeDependencies is the canonical hook to
  // capture provider references for use in dispose.
  RideFlowState? _flow;

  /// In-flight Find Cab request. Disables the button while we're round-
  /// tripping the backend so a double-tap doesn't fire twice. The
  /// authoritative source of "this rider already tapped" is
  /// `ride.isReadyToFindCab` (backend-persisted) — this is just for the
  /// optimistic UI between tap and response.
  bool _findingCab = false;
  String? _findCabError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flow = context.read<RideFlowState>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _flow?.startWatching();
    });
  }

  Future<void> _onFindCab(String tripId) async {
    setState(() {
      _findingCab = true;
      _findCabError = null;
    });
    try {
      final api = context.read<RideApi>();
      await api.findCabForTrip(tripId);
      // The next poll tick will refresh activeRide with readyToFindCab=true
      // and (eventually) status=driverAssigned once a driver accepts.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _findCabError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    } finally {
      if (mounted) setState(() => _findingCab = false);
    }
  }

  @override
  void dispose() {
    // Stop polling here — the live-ride screen takes over from this point and
    // will re-arm watching if needed.
    _flow?.stopWatching();
    super.dispose();
  }

  /// Co-rider just cancelled and we're now alone in the group. Give the
  /// rider a clear binary: keep this ride at the (higher) solo fare, or
  /// cancel + restart the search for a new co-rider. The fare shown is
  /// the freshly-recomputed solo amount (rebuilt by the polling watcher).
  Future<void> _showCoRiderLostDialog(double soloFare) async {
    final waitForAnother = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // force an explicit choice
      builder: (dCtx) => AlertDialog(
        title: const Text('Your co-rider cancelled'),
        content: Text(
          "You're the only rider now. Continue solo at ₹${soloFare.toStringAsFixed(0)} "
          '(the full fare), or wait for another co-rider to share with?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Continue solo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.brandDark),
            child: const Text('Wait for another'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final flow = context.read<RideFlowState>();
    if (waitForAnother == true) {
      // Cancel the now-solo trip and start a fresh 5-min search.
      await flow.searchForAnother();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(Routes.searching);
    } else {
      // Keep the trip as-is. The screen rebuilds with the solo fare; the
      // existing "I'm ready — track ride" CTA continues to work.
      flow.continueSolo();
    }
  }

  /// Confirm-then-cancel the active ride. We always wrap with an
  /// AlertDialog because cancellation is destructive — the trip is lost,
  /// the co-rider's app gets a "co-rider cancelled" snackbar, and any
  /// dispatched driver is freed.
  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          "You'll lose your match and the co-rider will be notified. "
          'You can always book a new ride afterwards.',
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

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    final ride = flow.activeRide;

    if (ride == null) {
      return const Scaffold(body: Center(child: Text('No active ride.')));
    }

    // Surface state-change toast from polling (e.g. "co-rider cancelled").
    final toast = flow.toastMessage;
    if (toast != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(toast),
            duration: const Duration(seconds: 3),
          ));
        context.read<RideFlowState>().clearToast();
      });
    }

    // Polling watcher just told us the rider lost ALL their co-riders —
    // pop a dialog asking whether to wait for another one or proceed solo.
    if (flow.coRiderLostPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Clear the flag immediately so a subsequent rebuild doesn't
        // re-trigger before the dialog closes.
        context.read<RideFlowState>().clearCoRiderLost();
        _showCoRiderLostDialog(ride.perRiderFare);
      });
    }

    final v = ride.driver.vehicle;
    // The chat is meaningful only when there's actually a co-rider to talk
    // to. Solo trips (riderCount == 1) hide the icon entirely.
    final hasCoRider = ride.proposal.riderCount >= 2;
    final groupId = ride.proposal.groupId;

    // Phase the screen by where we are in the post-match flow:
    //   - matched/no driver, gate open  → "Find Cab" CTA
    //   - matched/no driver, gate done  → "Looking for a driver / waiting"
    //   - driverAssigned (or later)     → "Driver on the way" with details
    final hasDriver = ride.driver.id.isNotEmpty &&
        ride.status != RideStatus.confirmed;
    final showFindCab =
        ride.status == RideStatus.confirmed && !ride.isReadyToFindCab;
    final waitingForDriver =
        ride.status == RideStatus.confirmed && ride.isReadyToFindCab;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          hasDriver
              ? 'Driver on the way'
              : (showFindCab ? 'Match confirmed' : 'Finding your cab'),
        ),
        actions: [
          if (hasCoRider && groupId != null)
            IconButton(
              tooltip: 'Chat with co-rider',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.of(context).pushNamed(
                Routes.chat,
                arguments: groupId,
              ),
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Phase header. Replaces what used to be the OTP-front-and-
            // centre card — OTP is meaningless until a driver is on the
            // way, so we surface phase-appropriate copy at the top and
            // move OTP below.
            if (showFindCab)
              _PhaseCard(
                icon: Icons.directions_car_outlined,
                title: hasCoRider
                    ? 'Ready to ride together?'
                    : 'Ready to find your cab?',
                body: hasCoRider
                    ? "Tap Find Cab when you're ready. Your co-rider has to "
                        'tap it too before we send the trip to a driver.'
                    : 'Tap Find Cab when you’re ready and we’ll dispatch the '
                        'nearest available driver.',
              )
            else if (waitingForDriver)
              _PhaseCard(
                icon: Icons.hourglass_top_outlined,
                title: 'Looking for a driver…',
                body: hasCoRider
                    ? 'We’ll start dispatch once your co-rider also taps '
                        'Find Cab. A nearby driver gets 30s to accept.'
                    : 'Sending the trip to the nearest driver. They have '
                        '30s to accept.',
                showProgress: true,
              )
            else
              // Driver assigned (or further). Surface the OTP prominently
              // — this is when it actually matters.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR PICKUP OTP',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          ride.otp,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: ride.otp));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('OTP copied')),
                            );
                          },
                          icon: const Icon(Icons.copy, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Share this only with the driver when they arrive at your pickup.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            if (_findCabError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_findCabError!, style: TextStyle(color: Colors.red.shade900))),
                  ],
                ),
              ),
            ],
            // Driver + vehicle cards only appear once a driver has actually
            // accepted. Before that the placeholder Driver doc would render
            // "Awaiting driver" / empty plate which read as broken state.
            if (hasDriver) ...[
              const SizedBox(height: 20),
              const _SectionTitle(title: 'Driver'),
              _Tile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.brandLight,
                  child: Text(
                    ride.driver.name.characters.first,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.brandDark),
                  ),
                ),
                title: ride.driver.name,
                subtitle: '${ride.driver.rating.toStringAsFixed(1)}★ · ${ride.driver.totalRides} rides',
                trailing: TextButton.icon(
                  onPressed: () {/* hook into masked-call */},
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionTitle(title: 'Vehicle'),
              _Tile(
                leading: const Icon(Icons.directions_car_outlined, size: 32, color: AppTheme.brand),
                title: '${v.color} ${v.model}',
                subtitle: '${v.type.label} · seats ${v.type.totalSeats}',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '••${v.plateLast4}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _SectionTitle(title: 'Your share'),
            // New itemised breakdown when the backend provided one (post-
            // pricing-rewrite trips). Falls back to the legacy single-line
            // display for old trips that don't carry the breakdown.
            if (ride.proposal.fareBreakdown != null)
              FareBreakdownCard(breakdown: ride.proposal.fareBreakdown!)
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'You pay only your part of the fare. Drivers receive the full amount.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '₹${ride.perRiderFare.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showFindCab)
                ElevatedButton.icon(
                  icon: const Icon(Icons.local_taxi_outlined),
                  label: Text(_findingCab ? 'Submitting…' : 'Find Cab'),
                  onPressed: _findingCab ? null : () => _onFindCab(ride.id),
                )
              else if (waitingForDriver)
                const ElevatedButton(
                  onPressed: null,
                  child: Text('Waiting for driver…'),
                )
              else
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed(Routes.liveRide),
                  child: const Text('Track ride'),
                ),
              TextButton(
                onPressed: () => _confirmCancel(context),
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                child: const Text('Cancel ride'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase header card — surfaces "what's happening right now" in the
/// post-match flow. Used for both the Find-Cab and waiting-for-driver
/// states; the driver-assigned phase has its own OTP card above.
class _PhaseCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool showProgress;
  const _PhaseCard({
    required this.icon,
    required this.title,
    required this.body,
    this.showProgress = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.brandDark, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.brandDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (showProgress) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(
                    backgroundColor: Colors.white,
                    valueColor: AlwaysStoppedAnimation(AppTheme.brandDark),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
