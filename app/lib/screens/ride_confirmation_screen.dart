import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vehicle.dart';
import '../routes.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride confirmed'),
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
                    'Share this with your driver only after they confirm the trip details.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle(title:'Driver'),
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
            const _SectionTitle(title:'Vehicle'),
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
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed(Routes.liveRide),
                child: const Text('I’m ready — track ride'),
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
