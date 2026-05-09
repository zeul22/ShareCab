import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/notification_service.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Active search state.
///
/// Lifecycle:
///   1. initState: kick off [RideFlowState.startSearch] (creates the trip).
///   2. Run a 5-minute progress bar. The flow's polling watcher updates the
///      proposal as backend state changes.
///   3. As soon as the flow stage transitions to `proposing` (a co-rider
///      paired up), navigate to MatchResultScreen.
///   4. If 5 minutes elapse with no match, stop the watcher, fire a system
///      notification, and show the empty-state UI (Search again / Cancel).
class SearchingScreen extends StatefulWidget {
  const SearchingScreen({super.key});

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen>
    with SingleTickerProviderStateMixin {
  // Match window per the product spec: 5 minutes. After this, give up and
  // show the empty state. Override via the `MATCH_SEARCH_WINDOW_MS` env on
  // the backend if you need a tighter loop for demo/QA.
  static const Duration _searchWindow = Duration(minutes: 5);

  late final AnimationController _progress;
  RideFlowState? _flow;
  bool _navigated = false;
  bool _timeoutReached = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _searchWindow)
      ..addStatusListener(_onProgressDone);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _flow = context.read<RideFlowState>();
      _flow!.addListener(_onFlowChange);

      // If a search is already in flight (rider navigated away and came
      // back via the global banner), resume the progress bar from where
      // it should be based on flow.searchStartedAt instead of restarting
      // from zero. Otherwise kick off a fresh search.
      if (_flow!.stage == FlowStage.searching && _flow!.searchStartedAt != null) {
        _resumeProgress(_flow!.searchStartedAt!);
      } else if (_flow!.stage == FlowStage.proposing &&
          _flow!.proposals.isNotEmpty) {
        // Match already landed before we got here — hand off immediately.
        _onFlowChange();
        return;
      } else {
        _progress.forward();
        await _flow!.startSearch();
      }
      // Cover the rare race where startSearch returned an already-matched
      // proposal (riderCount >= 2 immediately) — addListener won't fire for
      // state set before it was attached.
      _onFlowChange();
    });
  }

  /// Set the progress bar to the elapsed-since-startedAt position and continue
  /// from there. If the window has already elapsed (rider was away for >5min),
  /// snap to 1.0 and let _onProgressDone surface the empty state.
  void _resumeProgress(DateTime startedAt) {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final fraction = elapsed / _searchWindow.inMilliseconds;
    if (fraction >= 1.0) {
      _progress.value = 1.0;
      // Status listener will fire on completion — let it.
    } else {
      _progress.forward(from: fraction.clamp(0.0, 1.0));
    }
  }

  @override
  void dispose() {
    _flow?.removeListener(_onFlowChange);
    // Don't stopWatching here — that's owned by RideFlowState's own
    // lifecycle and the next screen (MatchResult / RideConfirmation) wants
    // it to keep running. We only stop watching on timeout (see below).
    _progress.removeStatusListener(_onProgressDone);
    _progress.dispose();
    super.dispose();
  }

  /// Hand off to MatchResultScreen the moment the flow says we have a real
  /// match (riderCount >= 2 → stage = proposing). Idempotent via [_navigated]
  /// so repeated rebuilds while we're transitioning don't double-push.
  void _onFlowChange() {
    final flow = _flow;
    if (flow == null || _navigated || !mounted) return;
    if (flow.stage == FlowStage.proposing && flow.proposals.isNotEmpty) {
      _navigated = true;
      Navigator.of(context).pushReplacementNamed(Routes.matchResult);
    }
  }

  /// Fired once when the AnimationController ticks past 1.0. If no match
  /// landed during the window, stop the polling watcher and let the empty
  /// state render.
  void _onProgressDone(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _navigated) return;
    final flow = _flow;
    if (flow == null) return;
    if (flow.proposals.isNotEmpty && flow.proposals.first.riderCount >= 2) {
      // Match landed in the same frame; the listener will navigate.
      return;
    }
    setState(() => _timeoutReached = true);
    flow.stopWatching();
    NotificationService.instance.searchTimedOut();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    final airport = flow.search.airportArrivalMode;

    return Scaffold(
      appBar: AppBar(
        // Back arrow (NOT close) — popping leaves the search running in
        // RideFlowState. The global RideFlowBanner will surface "still
        // searching" / "match found" wherever the rider goes next. To
        // outright cancel, the rider hits Cancel in the empty state UI
        // (or waits for the 5-min backend window to auto-cancel).
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Browse the app while we search',
          onPressed: () =>
              Navigator.of(context).popUntil(ModalRoute.withName(Routes.home)),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _timeoutReached ? _buildEmptyState(context) : _buildSearching(context, airport),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Active search UI
  // ---------------------------------------------------------------------------
  Widget _buildSearching(BuildContext context, bool airport) {
    final error = context.watch<RideFlowState>().error;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 4, color: AppTheme.brand),
        ),
        const SizedBox(height: 24),
        Text(
          airport
              ? 'Looking for landing co-passengers…'
              : 'Finding compatible co-passengers…',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'We\'ll notify you the moment a match is ready.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        // Surface backend errors (e.g. 409 if the rider already has an
        // in-flight trip) instead of silently spinning for 5 minutes.
        if (error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF1C0C0)),
            ),
            child: Text(
              error.replaceFirst(RegExp(r'^Exception:\s*'), ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: _progress,
          builder: (_, __) {
            final secsLeft =
                (_searchWindow.inSeconds * (1 - _progress.value)).ceil();
            final mm = (secsLeft ~/ 60).toString().padLeft(2, '0');
            final ss = (secsLeft % 60).toString().padLeft(2, '0');
            // Threshold: 60s of the 5-minute window → 0.2. Keeps the very
            // first stretch of the wait button-free (riders shouldn't bail
            // before the matching engine has had a real chance) and gives
            // an obvious off-ramp once it's been long enough to feel slow.
            final showCancel = _progress.value >= (60 / _searchWindow.inSeconds);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress.value,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE6E9EB),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.brand),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$mm:$ss left in this search window',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
                if (showCancel) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    onPressed: _cancelSearch,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancel search'),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// Active cancel — kills the in-flight trip on the backend and pops back
  /// to Home. Distinct from the AppBar back arrow, which only navigates and
  /// leaves the search running.
  Future<void> _cancelSearch() async {
    final flow = context.read<RideFlowState>();
    await flow.cancelActiveRide();
    if (!mounted) return;
    Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
  }

  // ---------------------------------------------------------------------------
  // Timeout / no-match UI
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF8E1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.people_outline, size: 40, color: Color(0xFF8A6D00)),
        ),
        const SizedBox(height: 18),
        const Text(
          'No co-rider this round',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'We searched for 5 minutes and didn\'t find anyone going your way. Try again — riders come and go quickly.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              setState(() {
                _timeoutReached = false;
                _navigated = false;
              });
              _progress
                ..reset()
                ..forward();
              await context.read<RideFlowState>().retrySearch();
              if (mounted) _onFlowChange();
            },
            child: const Text('Search again'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            context.read<RideFlowState>().clear();
            Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
