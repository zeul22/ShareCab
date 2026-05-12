import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/driver_profile.dart';
import '../routes.dart';
import '../services/api/driver_api.dart';
import '../services/auth_service.dart';
import '../services/location_push_service.dart';
import '../services/subscription_checkout.dart';
import '../theme/app_theme.dart';
import '../widgets/incoming_offer_sheet.dart';

/// Driver-mode landing screen. Polls `/drivers/me` every 12s while the
/// driver is online + unassigned so a fresh dispatch surfaces without a
/// manual reload. Cards:
///
///   - [_SubscriptionCard]  — only revenue surface; renew via Razorpay.
///   - [_OnlineToggleCard]  — gated on subscription; toggles location push.
///   - [_DispatchCard]      — empty state + active-dispatch CTA.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Two cadences. Fast cadence (3s) runs while online + unassigned so
  // an incoming offer surfaces within a few seconds of the rider booking.
  // Slow cadence (12s) is the steady-state when offline OR mid-trip — we
  // only need to detect macro changes (subscription expiry, manual
  // server-side flips).
  static const _slowPollInterval = Duration(seconds: 12);
  static const _fastPollInterval = Duration(seconds: 3);

  DriverProfile? _profile;
  bool _loading = true;
  bool _toggling = false;
  bool _renewing = false;
  String? _error;
  SubscriptionCheckout? _checkout;
  Timer? _poll;
  Duration _currentInterval = _slowPollInterval;
  // True while the IncomingOfferSheet is mounted, so the poll doesn't
  // stack a second sheet on a second poll tick while the driver is
  // already deciding on the first offer.
  bool _offerSheetOpen = false;

  DriverApi get _api => context.read<DriverApi>();
  LocationPushService get _locationPush => context.read<LocationPushService>();

  @override
  void initState() {
    super.initState();
    debugPrint('[home] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[home] postFrame — _refresh + start poll');
      _refresh();
      _startPoll(_slowPollInterval);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _checkout?.dispose();
    super.dispose();
  }

  /// (Re-)arm the periodic refresh at the given cadence. Cancels any
  /// existing timer first so cadence switches are atomic.
  void _startPoll(Duration interval) {
    if (_currentInterval == interval && _poll != null && _poll!.isActive) return;
    _poll?.cancel();
    _currentInterval = interval;
    _poll = Timer.periodic(interval, (_) => _refresh(silent: true));
    debugPrint('[home] poll cadence → ${interval.inSeconds}s');
  }

  Future<void> _refresh({bool silent = false}) async {
    debugPrint('[home] _refresh(silent=$silent)');
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await _api.getMyDriver();
      debugPrint('[home] getMyDriver ok — online=${p.isOnline} '
          'activeTrips=${p.activeTripIds.length} '
          'verification=${p.verificationStatus}');
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
      // Resume location pings if a prior session crashed before we could
      // stop them, or if the user came back to the app after the timer
      // was paused. Idempotent — no-op when already running.
      if (p.isOnline && !_locationPush.running) {
        debugPrint('[home] resuming location push (was online)');
        unawaited(_locationPush.start());
      } else if (!p.isOnline && _locationPush.running) {
        debugPrint('[home] stopping location push (now offline)');
        _locationPush.stop();
      }
      // Adaptive cadence: 3s while looking for an offer, 12s otherwise.
      // The fast cadence keeps perceived latency low when a rider books;
      // the slow cadence saves battery + backend load the rest of the time.
      final wantFast = p.isOnline && !p.hasActiveDispatch;
      _startPoll(wantFast ? _fastPollInterval : _slowPollInterval);

      // Auto-jump into an active trip if one came in while we were on
      // home. Pushed (not replaced) so back lands on home.
      if (p.hasActiveDispatch && ModalRoute.of(context)?.isCurrent == true) {
        debugPrint('[home] auto-pushing → activeTrip '
            '(${p.activeTripIds.length} trips)');
        Navigator.of(context).pushNamed(Routes.activeTrip);
      } else if (wantFast && !_offerSheetOpen) {
        // Check for a pending offer alongside the profile. The /me/offer
        // endpoint is cheap (one indexed Mongo lookup, 204 in the common
        // case) and only fires the sheet when there's actually something
        // to act on. Sheet-open guard prevents stacking on rapid ticks.
        await _checkForPendingOffer();
      }
    } catch (e) {
      debugPrint('[home] _refresh threw: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) {
          _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        }
      });
    }
  }

  /// Hits `GET /drivers/me/offer`. If the response carries a pending
  /// offer, shows the [IncomingOfferSheet] and dispatches the result to
  /// the backend. Sheet-open guard via [_offerSheetOpen] keeps the next
  /// poll tick from stacking a second sheet on the same offer.
  Future<void> _checkForPendingOffer() async {
    if (_offerSheetOpen) return;
    final offer = await _api.getMyOffer();
    if (offer == null || !mounted) return;

    debugPrint('[home] incoming offer trip=${offer.tripId} '
        'expiresIn=${offer.secondsRemaining()}s');
    _offerSheetOpen = true;
    try {
      final result = await IncomingOfferSheet.show(context, offer);
      if (!mounted) return;
      switch (result) {
        case OfferAccepted():
          debugPrint('[home] driver tapped ACCEPT — calling backend');
          try {
            await _api.acceptOffer(offer.tripId);
          } catch (e) {
            // Backend can 409 if the offer already expired between the
            // sheet showing and the tap landing. Treat as expired —
            // next poll picks up whatever comes next.
            debugPrint('[home] acceptOffer threw: $e');
            if (mounted) {
              setState(() => _error =
                  'Offer no longer available. Waiting for the next one.');
            }
          }
          // Next /drivers/me poll surfaces hasActiveDispatch=true →
          // existing code path auto-pushes to ActiveTripScreen.
          unawaited(_refresh(silent: true));
        case OfferRejected():
          debugPrint('[home] driver tapped REJECT — calling backend');
          try {
            await _api.rejectOffer(offer.tripId);
          } catch (e) {
            debugPrint('[home] rejectOffer threw: $e');
          }
        case OfferExpired():
          // Backend's own timer already auto-rejected on the wire. No
          // need to call /reject — would just 409 ("not_offered").
          debugPrint('[home] offer expired locally');
      }
    } finally {
      if (mounted) _offerSheetOpen = false;
    }
  }

  Future<void> _toggleOnline(bool wantOnline) async {
    if (_toggling) return;
    setState(() {
      _toggling = true;
      _error = null;
    });
    try {
      final p =
          wantOnline ? await _api.setOnline() : await _api.setOffline();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _toggling = false;
      });
      if (wantOnline) {
        await _locationPush.start();
      } else {
        _locationPush.stop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _toggling = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  /// Renewal flow: backend creates a Razorpay order; in stub mode we
  /// confirm with a synthetic paymentRef so local demos work without
  /// real keys. SubscriptionCheckout handles both paths internally.
  Future<void> _renew() async {
    if (_renewing) return;
    final auth = context.read<AuthService>();
    final user = auth.user;
    if (user == null) return;

    setState(() {
      _renewing = true;
      _error = null;
    });
    final checkout = SubscriptionCheckout(api: _api);
    _checkout = checkout;
    try {
      final result = await checkout.renew(user: user);
      if (!mounted) return;
      switch (result) {
        case CheckoutSuccess(:final profile):
          setState(() {
            _profile = profile;
            _renewing = false;
          });
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('Subscription renewed.'),
              duration: Duration(seconds: 2),
            ));
        case CheckoutCancelled():
          setState(() => _renewing = false);
        case CheckoutFailed(:final message):
          setState(() {
            _renewing = false;
            _error = message;
          });
      }
    } finally {
      checkout.dispose();
      if (identical(_checkout, checkout)) _checkout = null;
    }
  }

  Future<void> _signOut() async {
    _locationPush.stop();
    final auth = context.read<AuthService>();
    await auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(Routes.phoneEntry, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver mode'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (v) async {
              if (v == 'profile') {
                Navigator.of(context).pushNamed(Routes.profile);
              } else if (v == 'logout') {
                await _signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile')),
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.brand,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Hi ${auth.user?.name ?? 'driver'}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Manage your subscription and pickups from here.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                _ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              if (_loading && _profile == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_profile != null) ...[
                _SubscriptionCard(
                  profile: _profile!,
                  renewing: _renewing,
                  onRenew: _renew,
                ),
                const SizedBox(height: 16),
                _OnlineToggleCard(
                  profile: _profile!,
                  toggling: _toggling,
                  onChanged: _toggleOnline,
                ),
                const SizedBox(height: 16),
                _DispatchCard(
                  profile: _profile!,
                  onOpen: () async {
                    await Navigator.of(context).pushNamed(Routes.activeTrip);
                    if (!mounted) return;
                    await _refresh();
                  },
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Earnings, ride history, support — coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SubscriptionCard extends StatelessWidget {
  final DriverProfile profile;
  final bool renewing;
  final VoidCallback onRenew;
  const _SubscriptionCard({
    required this.profile,
    required this.renewing,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    final sub = profile.subscription;
    final active = sub.isSubscribed;
    final daysLeft = sub.daysLeft;
    final exp = sub.expiresAt;
    final urgent = active && daysLeft != null && daysLeft <= 3;

    final bg = active
        ? (urgent ? const Color(0xFFFFF5E6) : AppTheme.brandLight)
        : const Color(0xFFFFEFEF);
    final fg = active
        ? (urgent ? const Color(0xFF8A4A00) : AppTheme.brandDark)
        : const Color(0xFFB00020);

    String headline;
    if (!active) {
      headline = 'Subscription expired';
    } else if (sub.isFreeTrial) {
      headline = 'Free trial · ${daysLeft ?? 0} day${daysLeft == 1 ? '' : 's'} left';
    } else {
      headline = 'Active · ${daysLeft ?? 0} day${daysLeft == 1 ? '' : 's'} left';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.workspace_premium : Icons.lock_outline,
                color: fg,
              ),
              const SizedBox(width: 8),
              Text(
                'SUBSCRIPTION',
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          const SizedBox(height: 4),
          if (exp != null)
            Text(
              active
                  ? 'Expires ${_formatDate(exp)}'
                  : 'Expired ${_formatDate(exp)}. You can\'t go online until you renew.',
              style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.35),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: renewing ? null : onRenew,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    active ? AppTheme.brand : Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: renewing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(active ? 'Renew now' : 'Renew to go online'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ---------------------------------------------------------------------------

class _OnlineToggleCard extends StatelessWidget {
  final DriverProfile profile;
  final bool toggling;
  final ValueChanged<bool> onChanged;

  const _OnlineToggleCard({
    required this.profile,
    required this.toggling,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canGoOnline = profile.subscription.isSubscribed;
    final isOnline = profile.isOnline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isOnline ? AppTheme.brand : Colors.black26,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'Online — receiving dispatches' : 'Offline',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  canGoOnline
                      ? (isOnline
                          ? 'Toggle off when you\'re done for the day.'
                          : 'Flip the switch to start accepting riders.')
                      : 'Renew your subscription to go online.',
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          if (toggling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            Switch.adaptive(
              value: isOnline,
              activeThumbColor: AppTheme.brand,
              onChanged: canGoOnline ? onChanged : null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DispatchCard extends StatelessWidget {
  final DriverProfile profile;
  final VoidCallback onOpen;
  const _DispatchCard({required this.profile, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final n = profile.activeTripIds.length;
    if (n == 0) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: const Row(
          children: [
            Icon(Icons.directions_car_outlined,
                color: Colors.black38, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No active dispatch.\nGo online to receive your first ride.',
                style: TextStyle(color: Colors.black54, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: AppTheme.brand,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.directions_car,
                  color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$n active ${n == 1 ? 'rider' : 'riders'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      'Tap to view route & start the trip',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1C0C0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFB00020), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: Color(0xFFB00020), fontSize: 13, height: 1.35),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            iconSize: 18,
            onPressed: onDismiss,
            icon: const Icon(Icons.close, color: Color(0xFFB00020)),
          ),
        ],
      ),
    );
  }
}
