import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/driver_profile.dart';
import '../routes.dart';
import '../services/api/driver_api.dart';
import '../services/auth_service.dart';
import '../services/subscription_checkout.dart';
import '../theme/app_theme.dart';

/// Driver-mode landing screen. Mirrors the rider's [HomeScreen] role:
///
///   - Greets the driver
///   - Surfaces subscription status (the only revenue surface for drivers)
///   - Lets them toggle online / offline (backend rejects if sub expired)
///   - Shows the dispatch card; tapping it pushes [DriverActiveTripScreen]
///     where the trip lifecycle (arrive → start → complete) lives.
///
/// Loads `GET /api/drivers/me` on init + refresh, and polls every 12s while
/// online + unassigned so a fresh dispatch surfaces without a manual reload.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  // Light poll so a newly assigned dispatch surfaces without the driver
  // having to pull-to-refresh. 12s is a balance between responsiveness
  // and battery — when the trip is live, the active-trip screen polls
  // tighter (8s) for the same reason.
  static const _pollInterval = Duration(seconds: 12);

  DriverProfile? _profile;
  bool _loading = true;
  bool _toggling = false;
  bool _renewing = false;
  String? _error;
  SubscriptionCheckout? _checkout;
  Timer? _poll;

  DriverApi get _api => context.read<DriverApi>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _checkout?.dispose();
    super.dispose();
  }

  /// Reload the driver profile. `silent: true` skips the loading spinner
  /// (used by the poll tick) so the UI doesn't blink every 12s.
  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await _api.getMyDriver();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Don't blow away an existing _error on silent ticks.
        if (!silent) {
          _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        }
      });
    }
  }

  Future<void> _toggleOnline(bool wantOnline) async {
    if (_toggling) return;
    setState(() {
      _toggling = true;
      _error = null;
    });
    try {
      final p = wantOnline ? await _api.setOnline() : await _api.setOffline();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _toggling = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _toggling = false;
        // Backend's 403 message guides them to renew — surface it verbatim.
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  /// Renew flow:
  ///   1. Disable the CTA (set [_renewing]) so we can't double-fire.
  ///   2. Create a fresh [SubscriptionCheckout] (Razorpay clears its native
  ///      handlers on dispose, so reusing across renewals would leak).
  ///   3. Hand off to [SubscriptionCheckout.renew] — it handles stub vs
  ///      real Razorpay internally.
  ///   4. On success, refresh `_profile` from the returned doc so the
  ///      subscription card flips to "Active · 30 days left" immediately.
  Future<void> _renew() async {
    if (_renewing) return;
    final auth = context.read<AuthService>();
    final user = auth.user;
    if (user == null) return; // Defensive; logged-out users can't reach here.

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
      // Dispose the checkout instance now that the future has settled —
      // we'll build a new one for the next renewal attempt.
      checkout.dispose();
      if (identical(_checkout, checkout)) _checkout = null;
    }
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
              if (v == 'logout') {
                await context.read<AuthService>().logout();
                if (!context.mounted) return;
                Navigator.of(context)
                    .pushNamedAndRemoveUntil(Routes.phoneEntry, (_) => false);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Hi ${auth.user?.name ?? 'driver'} 👋',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Manage your subscription and pickups from here.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),

              if (_error != null)
                _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),

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
                    // Push the lifecycle screen and refresh once the
                    // driver returns — they may have completed the trip,
                    // which clears activeTrips on the server.
                    await Navigator.of(context)
                        .pushNamed(Routes.driverActiveTrip);
                    if (!mounted) return;
                    await _refresh();
                  },
                ),
              ],

              const SizedBox(height: 24),
              const Text(
                'Driver settings, ride history, support — coming soon.',
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
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13, height: 1.35),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: renewing ? null : onRenew,
              style: ElevatedButton.styleFrom(
                backgroundColor: active ? AppTheme.brand : Colors.red.shade700,
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
    final months = [
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  canGoOnline
                      ? (isOnline
                          ? 'Toggle off when you\'re done for the day.'
                          : 'Flip the switch to start accepting riders.')
                      : 'Renew your subscription to go online.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.35),
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
            Icon(Icons.directions_car_outlined, color: Colors.black38, size: 28),
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
              const Icon(Icons.directions_car, color: Colors.white, size: 28),
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
          const Icon(Icons.error_outline, color: Color(0xFFB00020), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 13, height: 1.35),
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
