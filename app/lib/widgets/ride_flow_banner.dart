import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Bottom-floating banner that surfaces in-flight ride state on every screen
/// EXCEPT the screens that already render that state natively
/// ([Routes.searching], [Routes.matchResult], [Routes.rideConfirmation]).
///
/// While a search is running it shows a live 5-minute countdown bar
/// computed from [RideFlowState.searchStartedAt] — so a rider who hits the
/// back arrow on SearchingScreen can still see how much wait window is
/// left from anywhere in the app. Tapping the banner takes them back to
/// the relevant screen.
class RideFlowBanner extends StatefulWidget {
  /// Tracks the topmost route's name. Wired by `_CurrentRouteObserver` in
  /// `main.dart`. Used to hide the banner when the user is already on the
  /// screen that natively shows this state.
  final ValueListenable<String?> currentRoute;

  /// Navigator we drive when the rider taps the banner. Provided from
  /// `main.dart` because the banner sits above the Navigator in the tree.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Search window length. Mirrors the AnimationController in
  /// SearchingScreen and the backend's `MATCH_DISPATCH_DELAY_MS`.
  static const Duration searchWindow = Duration(minutes: 5);

  const RideFlowBanner({
    super.key,
    required this.currentRoute,
    required this.navigatorKey,
  });

  @override
  State<RideFlowBanner> createState() => _RideFlowBannerState();
}

class _RideFlowBannerState extends State<RideFlowBanner> {
  // 1Hz tick so the countdown bar advances smoothly between polling
  // cycles. Started/stopped based on whether a search is actually in flight,
  // so we don't burn frames on screens with no active state.
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _ensureTicker(bool needed) {
    if (needed && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: widget.currentRoute,
      builder: (_, route, __) => Consumer<RideFlowState>(
        builder: (_, flow, __) {
          final spec = _bannerSpecFor(flow, route);
          // Tick only while there's something to count down for.
          _ensureTicker(spec?.kind == _BannerKind.searching);
          if (spec == null) return const SizedBox.shrink();
          return _Banner(
            spec: spec,
            onTap: () => _handleTap(spec),
            onCancel: spec.showCancel ? () => _handleCancel(flow) : null,
          );
        },
      ),
    );
  }

  void _handleTap(_BannerSpec spec) {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamed(spec.targetRoute);
  }

  /// X-on-banner cancel — same backend cleanup as RideFlowState.cancelActiveRide
  /// (the SearchingScreen + RideConfirmation cancel buttons share this code
  /// path). Banner disappears as soon as state clears.
  Future<void> _handleCancel(RideFlowState flow) async {
    await flow.cancelActiveRide();
  }

  /// Decide which banner (if any) to render for the given flow state +
  /// current route. Returns null when no banner is appropriate.
  _BannerSpec? _bannerSpecFor(RideFlowState flow, String? currentRoute) {
    // 1. Match landed but not yet confirmed → preempts everything else.
    if (flow.stage == FlowStage.proposing && flow.proposals.isNotEmpty) {
      if (currentRoute == Routes.matchResult ||
          currentRoute == Routes.rideConfirmation) {
        return null;
      }
      return const _BannerSpec(
        kind: _BannerKind.matchFound,
        title: 'Match found',
        subtitle: 'Tap to confirm or reject',
        targetRoute: Routes.matchResult,
        progress: 1.0,
      );
    }

    // 2. Search in flight → progress bar over the 5-min wait window.
    if (flow.stage == FlowStage.searching && flow.proposals.isNotEmpty) {
      if (currentRoute == Routes.searching) return null;

      final startedAt = flow.searchStartedAt;
      double fraction;
      String subtitle;
      var elapsedSeconds = 0;
      if (startedAt == null) {
        fraction = 0;
        subtitle = 'Tap to see your search progress';
      } else {
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
        elapsedSeconds = (elapsedMs / 1000).floor();
        fraction =
            (elapsedMs / RideFlowBanner.searchWindow.inMilliseconds).clamp(0.0, 1.0);
        final secsLeft = ((1 - fraction) *
                RideFlowBanner.searchWindow.inSeconds)
            .ceil();
        final mm = (secsLeft ~/ 60).toString().padLeft(2, '0');
        final ss = (secsLeft % 60).toString().padLeft(2, '0');
        subtitle = '$mm:$ss left · tap to view';
      }

      return _BannerSpec(
        kind: _BannerKind.searching,
        title: 'Looking for a co-rider…',
        subtitle: subtitle,
        targetRoute: Routes.searching,
        progress: fraction,
        // After 1 minute the rider gets an inline cancel — same threshold
        // as the SearchingScreen's button. Keeps the early window
        // commitment-only (don't bail prematurely) while offering an
        // off-ramp once it actually feels slow.
        showCancel: elapsedSeconds >= 60,
      );
    }

    // 3. Active dispatched ride → take the rider back to the live ride.
    //    Triggers when they back out of RideConfirmation / live ride.
    if (flow.activeRide != null) {
      if (currentRoute == Routes.rideConfirmation ||
          currentRoute == Routes.liveRide ||
          currentRoute == Routes.payment ||
          currentRoute == Routes.rating) {
        return null;
      }
      return const _BannerSpec(
        kind: _BannerKind.matchFound,
        title: 'Ride in progress',
        subtitle: 'Tap to view your ride',
        targetRoute: Routes.rideConfirmation,
        progress: 1.0,
      );
    }

    return null;
  }
}

enum _BannerKind { searching, matchFound }

class _BannerSpec {
  final _BannerKind kind;
  final String title;
  final String subtitle;
  final String targetRoute;
  // 0.0 → 1.0 fill of the progress bar at the bottom of the banner.
  final double progress;
  // True once the search has been running long enough (>=60s) that the
  // rider should see an explicit cancel affordance on the banner itself,
  // not just by navigating into SearchingScreen.
  final bool showCancel;

  const _BannerSpec({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.targetRoute,
    required this.progress,
    this.showCancel = false,
  });
}

class _Banner extends StatelessWidget {
  final _BannerSpec spec;
  final VoidCallback onTap;
  // Set when [_BannerSpec.showCancel] is true. Renders an X button at the
  // right edge that kills the in-flight trip. Null = no cancel UI.
  final VoidCallback? onCancel;

  const _Banner({required this.spec, required this.onTap, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isMatch = spec.kind == _BannerKind.matchFound;
    final bg = isMatch ? AppTheme.brand : Colors.black87;
    const fg = Colors.white;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          elevation: 8,
          shadowColor: Colors.black38,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Row(
                    children: [
                      if (isMatch)
                        const Icon(Icons.check_circle, color: fg, size: 22)
                      else
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(fg),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              spec.title,
                              style: const TextStyle(
                                color: fg,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              spec.subtitle,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Inline cancel: appears only after the search has
                      // been running long enough that the rider deserves
                      // an off-ramp on every screen, not just by going
                      // back into SearchingScreen.
                      if (onCancel != null)
                        InkWell(
                          onTap: onCancel,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, color: fg, size: 20),
                          ),
                        ),
                      const Icon(Icons.keyboard_arrow_up, color: fg),
                    ],
                  ),
                ),
                // Live countdown bar (only meaningful while searching; for the
                // match-found / active-ride states it stays full as a stable
                // visual baseline).
                LinearProgressIndicator(
                  value: spec.progress,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
