import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/match_proposal.dart';
import '../models/vehicle.dart';
import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';
import '../widgets/match_unlock_sheet.dart';

/// Shows the candidate match(es). User can accept, reject, or search again.
///
/// Polls every 2s via [RideFlowState] so changes from other riders (e.g. the
/// co-rider rejected the same group) are reflected here without manual refresh.
class MatchResultScreen extends StatefulWidget {
  const MatchResultScreen({super.key});

  @override
  State<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends State<MatchResultScreen>
    with SingleTickerProviderStateMixin {
  // Netflix-style "next episode" countdown: a draining bar that gives the
  // rider a finite window to confirm or reject the match. If they don't act,
  // we auto-reject — the safer default (no surprise commitments) and
  // mirrors the existing Reject button's behaviour exactly.
  //
  // Bumped from 60s → 5 min once the AdMob unlock gate landed: riders
  // now have to watch 2 rewarded ads (~30s each) before they can even
  // see the co-rider details. 60s wasn't enough; 5 min covers the ad
  // flow + a normal decision pause with margin.
  static const Duration _decisionWindow = Duration(minutes: 5);
  late final AnimationController _decisionTimer;
  bool _autoActed = false;
  // Tracks which proposal ids we've already opened the unlock sheet for
  // (rider-only mode). Re-opening on every rebuild would loop the sheet
  // back as soon as the user dismisses it.
  final Set<String> _unlockSheetShownFor = {};

  @override
  void initState() {
    super.initState();
    _decisionTimer = AnimationController(
      vsync: this,
      duration: _decisionWindow,
      value: 1.0, // start full, then drain to 0
    )
      ..reverse()
      ..addStatusListener(_onDecisionWindowExpired);

    // Defer to first frame so context.read works; the flow has the active
    // proposal id by the time this screen is reached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RideFlowState>().startWatching();
    });
  }

  /// Top-of-screen draining bar with a live mm:ss caption. Goes red in
  /// the last 30s so the colour-cue is still meaningful against the
  /// longer 5-minute window (a 10s threshold would only kick in for
  /// the final ~3% of the bar, too late to register).
  Widget _buildDecisionBar() {
    return AnimatedBuilder(
      animation: _decisionTimer,
      builder: (_, __) {
        final secsLeft =
            (_decisionWindow.inSeconds * _decisionTimer.value).ceil();
        final mm = (secsLeft ~/ 60).toString().padLeft(2, '0');
        final ss = (secsLeft % 60).toString().padLeft(2, '0');
        final urgent = secsLeft <= 30;
        final color = urgent ? Colors.red.shade700 : AppTheme.brand;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Confirm or reject — auto-rejects in $mm:$ss',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  // _decisionTimer.value drains 1.0 → 0.0, so the bar visibly
                  // shrinks (Netflix-style) rather than fills.
                  value: _decisionTimer.value,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE6E9EB),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Auto-reject if the rider doesn't act before the bar empties. Idempotent
  /// via [_autoActed] so a one-frame race between the timer firing and a
  /// manual tap can't double-cancel.
  void _onDecisionWindowExpired(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !mounted || _autoActed) return;
    final flow = context.read<RideFlowState>();
    if (flow.proposals.isEmpty) return; // already rejected/cleared
    _autoActed = true;
    flow.rejectProposal(flow.proposals.first);
  }

  @override
  void dispose() {
    _decisionTimer.removeStatusListener(_onDecisionWindowExpired);
    _decisionTimer.dispose();
    // Polling persists across MatchResult → RideConfirmation transitions so
    // we don't tear it down on dispose; the next screen restarts it.
    super.dispose();
  }

  /// Open the unlock sheet for a gated (rider-only, redacted) proposal.
  /// On success the polling watcher picks up the unredacted trip on the
  /// next 2s tick and `gatedUnlock` flips false automatically — so we
  /// don't need to refresh anything here. Dismissal pops back to home
  /// (the user can search again without paying).
  Future<void> _showUnlockSheet(MatchProposal proposal) async {
    _unlockSheetShownFor.add(proposal.id);
    final result = await MatchUnlockSheet.show(
      context,
      tripId: proposal.id,
    );
    if (!mounted) return;
    switch (result) {
      case MatchUnlockedSuccess():
        // Polling will refresh the proposal within 2s. Nothing to do.
        break;
      case MatchUnlockCancelled():
        // User backed out — go home so they're not staring at a
        // redacted match they can't act on.
        Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
      case MatchUnlockFailed(:final message):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    final proposals = flow.proposals;

    // Rider-only mode: backend redacted the co-rider on this trip. Open
    // the unlock sheet (one-time per proposal id) so the user can watch
    // ads or pay to reveal the details. Deferred to post-frame so
    // showModalBottomSheet has a real BuildContext to attach to.
    if (proposals.isNotEmpty &&
        proposals.first.gatedUnlock &&
        !_unlockSheetShownFor.contains(proposals.first.id)) {
      final gated = proposals.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showUnlockSheet(gated);
      });
    }

    // Surface state-change events from polling as a snackbar (then clear it
    // so the same toast doesn't fire on every rebuild).
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

    // No proposals left (manual reject / external cancel) → stop the drain
    // bar from animating uselessly and let the empty state take over.
    if (proposals.isEmpty && _decisionTimer.isAnimating) {
      _decisionTimer.stop();
    }

    // Intercept back (AppBar arrow, gesture, hardware) so the rider
    // doesn't accidentally bounce to an arbitrary previous route.
    //   - With an active proposal in front of them: cancel the trip
    //     and go home — they can't act on two rides at once, and
    //     letting the trip linger just blocks future searches.
    //   - With an empty list (co-rider just left, polling for the
    //     next): preserve the trip and go home. The floating banner
    //     surfaces "still searching" so the rider can drop back in.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBack(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compatible matches'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to home',
            onPressed: _handleBack,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (proposals.isNotEmpty) _buildDecisionBar(),
              Expanded(
                child: proposals.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: proposals.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => _ProposalCard(proposal: proposals[i]),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(Routes.searching),
              child: const Text('Search again'),
            ),
          ),
        ),
      ),
    );
  }

  /// Back-button handler used by both PopScope (gesture / hardware
  /// back) and the AppBar leading icon. When the screen is showing a
  /// live proposal, the rider tapping back means "I'm giving up on
  /// this match" — cancel the trip server-side so they can start a
  /// fresh booking without "you already have an active trip" errors.
  /// When the screen is showing the empty state (no current proposal,
  /// either co-rider just left or polling hasn't returned anyone yet),
  /// the trip is still searching server-side — preserve it and just
  /// take the rider home, where the floating banner gives them a way
  /// back in.
  Future<void> _handleBack() async {
    if (!mounted) return;
    final flow = context.read<RideFlowState>();
    final hasLiveProposal = flow.proposals.isNotEmpty;
    if (hasLiveProposal) {
      // Stop the auto-reject timer so it can't double-fire while we're
      // awaiting the cancel round-trip.
      _autoActed = true;
      _decisionTimer.stop();
      await flow.cancelActiveRide();
    }
    if (!mounted) return;
    Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 56, color: Colors.black26),
            const SizedBox(height: 16),
            const Text(
              'No compatible riders right now',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try again in a minute or switch to random-compatible mode.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(Routes.searching),
              child: const Text('Search again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final MatchProposal proposal;
  const _ProposalCard({required this.proposal});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${proposal.riderCount} riders',
                    style: const TextStyle(
                      color: AppTheme.brandDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  proposal.vehicleType.label,
                  style: const TextStyle(color: Colors.black54),
                ),
                const Spacer(),
                Text(
                  '₹${proposal.perRiderFare.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandDark,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Group total ₹${proposal.groupFare.toStringAsFixed(0)} · '
              '${proposal.distanceKm.toStringAsFixed(1)} km · ${proposal.durationMin} min',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          const Divider(height: 1),

          // Co-passengers
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Co-passengers',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...proposal.coPassengers.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.brandLight,
                            child: Text(
                              p.firstName.characters.first,
                              style: const TextStyle(
                                color: AppTheme.brandDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Name + rating on top, dropoff address (often a
                          // long reverse-geocoded string) on its own line
                          // below with ellipsis. Without the Expanded, long
                          // addresses overflow the row and squeeze the name
                          // column down to a single-character width.
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${p.firstName} · ${p.rating.toStringAsFixed(1)}★',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p.dropoff.address.isEmpty
                                      ? 'Drop nearby'
                                      : p.dropoff.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                _CapacityBar(
                  used: proposal.luggageSeatsUsed,
                  free: proposal.luggageSeatsFree,
                  vehicle: proposal.vehicleType,
                ),
                const SizedBox(height: 16),

                // Stops preview entry
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(Routes.routeStops, arguments: proposal),
                  icon: const Icon(Icons.alt_route),
                  label: const Text('See route & stops'),
                ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            context.read<RideFlowState>().rejectProposal(proposal),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await context.read<RideFlowState>().acceptProposal(proposal);
                          if (!context.mounted) return;
                          final ride =
                              context.read<RideFlowState>().activeRide;
                          if (ride == null) return;
                          // Rider-only mode: no driver assigned (empty
                          // id). Skip the driver-tracking screens and
                          // land on the coordination screen — co-rider
                          // info + chat + "we're done" close button.
                          final next = ride.driver.id.isEmpty
                              ? Routes.riderCoordination
                              : Routes.rideConfirmation;
                          Navigator.of(context).pushReplacementNamed(next);
                        },
                        child: const Text('Accept match'),
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

class _CapacityBar extends StatelessWidget {
  final int used;
  final int free;
  final VehicleType vehicle;
  const _CapacityBar({required this.used, required this.free, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final total = used + free;
    final ratio = total == 0 ? 0.0 : used / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Luggage space',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Spacer(),
            Text(
              '$used used · $free free',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: const Color(0xFFE6E9EB),
            valueColor: const AlwaysStoppedAnimation(AppTheme.brand),
          ),
        ),
      ],
    );
  }
}
