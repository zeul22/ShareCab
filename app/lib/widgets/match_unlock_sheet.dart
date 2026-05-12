import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ad_service.dart';
import '../services/api/ride_api.dart';
import '../services/auth_service.dart';
import '../services/unlock_checkout.dart';
import '../theme/app_theme.dart';

/// Outcome of [MatchUnlockSheet.show]. The caller pattern-matches: on
/// [Unlocked], refresh the trip; on [Cancelled], pop back / keep
/// the redacted view; on [Failed], surface the message.
sealed class MatchUnlockResult {
  const MatchUnlockResult();
}

class MatchUnlockedSuccess extends MatchUnlockResult {
  const MatchUnlockedSuccess();
}

class MatchUnlockCancelled extends MatchUnlockResult {
  const MatchUnlockCancelled();
}

class MatchUnlockFailed extends MatchUnlockResult {
  final String message;
  const MatchUnlockFailed(this.message);
}

/// "Match found — unlock to coordinate" bottom sheet. Shown post-match
/// when the trip is redacted (rider-only mode). Two paths:
///   - Watch [adsRequired] rewarded ads → backend mints unlock → unlock
///     match on this trip → close sheet with [MatchUnlockedSuccess].
///   - Pay (Razorpay) → backend mints unlock → unlock match → close.
///
/// Sheet manages its own state (ad counter, busy flag, error banner).
/// Caller just awaits the [show] future and acts on the result.
class MatchUnlockSheet extends StatefulWidget {
  /// Trip to consume the unlock against on success. Null when the sheet
  /// is opened PRE-TRIP (driver-dispatch mode, 402 from /trips) — in
  /// that case we just MINT the unlock and the next /trips call picks
  /// it up automatically via the backend's findOneAndUpdate consumption.
  final String? tripId;
  /// How many rewarded ads the rider needs to watch. Source of truth
  /// is the backend's adsRequiredForRating; UI mirror is fine here
  /// because the backend re-validates.
  final int adsRequired;
  /// Unlock price in paise (₹50 → 5000). UI shows this on the pay button.
  final int unlockPricePaise;

  const MatchUnlockSheet({
    super.key,
    this.tripId,
    this.adsRequired = 2,
    this.unlockPricePaise = 5000,
  });

  /// Convenience launcher. Returns the outcome so the caller doesn't
  /// have to handle the showModalBottomSheet plumbing. Pass `tripId: null`
  /// for the pre-trip mint flow (driver-dispatch mode).
  static Future<MatchUnlockResult> show(
    BuildContext context, {
    String? tripId,
    int adsRequired = 2,
    int unlockPricePaise = 5000,
  }) async {
    final result = await showModalBottomSheet<MatchUnlockResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => MatchUnlockSheet(
        tripId: tripId,
        adsRequired: adsRequired,
        unlockPricePaise: unlockPricePaise,
      ),
    );
    return result ?? const MatchUnlockCancelled();
  }

  @override
  State<MatchUnlockSheet> createState() => _MatchUnlockSheetState();
}

class _MatchUnlockSheetState extends State<MatchUnlockSheet> {
  int _adsWatched = 0;
  bool _adInProgress = false;
  bool _paying = false;
  String? _error;

  RideApi get _api => context.read<RideApi>();

  Future<void> _watchAd() async {
    if (_adInProgress || _adsWatched >= widget.adsRequired) return;
    setState(() {
      _adInProgress = true;
      _error = null;
    });

    final result = await AdService.instance.showRewardedAd();
    if (!mounted) return;

    switch (result) {
      case AdRewardEarned():
        final newCount = _adsWatched + 1;
        setState(() {
          _adsWatched = newCount;
          _adInProgress = false;
        });
        // If the rider has hit the threshold, mint the unlock + reveal.
        if (newCount >= widget.adsRequired) {
          await _finalizeUnlockViaAds();
        }
      case AdDismissed():
        setState(() {
          _adInProgress = false;
          _error = 'Ad was dismissed before completing — try again.';
        });
      case AdFailed(:final message):
        setState(() {
          _adInProgress = false;
          _error = message;
        });
    }
  }

  /// Backend confirms the ad count → mints an Unlock → we consume it
  /// against this trip in one combined step. If either call fails we
  /// surface the message and let the rider retry.
  Future<void> _finalizeUnlockViaAds() async {
    try {
      await _api.recordAdRewardForUnlock(adsCompleted: _adsWatched);
      // tripId == null → pre-trip mint flow (driver-dispatch mode 402
      // recovery). Just leave the freshly-minted Unlock in the
      // collection; the next /trips POST consumes it via the backend's
      // findOneAndUpdate. tripId != null → rider-only mode, consume
      // against the specific matched trip.
      final tid = widget.tripId;
      if (tid != null) {
        await _api.unlockMatchForTrip(tid);
      }
      if (!mounted) return;
      Navigator.of(context).pop(const MatchUnlockedSuccess());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _clean(e);
        // Reset so the rider can try again with the same number of ads —
        // the backend gate is idempotent on count, so re-calling with
        // the same total works.
      });
    }
  }

  Future<void> _pay() async {
    if (_paying) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    // Capture service refs upfront — we cross multiple async gaps and
    // can't safely read from `context` after the first await.
    final user = context.read<AuthService>().user;
    if (user == null) {
      // Logged-out riders shouldn't reach this sheet, but defensive:
      // bail with a clear message rather than crash on null.
      setState(() {
        _paying = false;
        _error = 'You are not signed in.';
      });
      return;
    }
    final checkout = UnlockCheckout(api: _api);
    try {
      // UnlockCheckout creates the Razorpay order, opens the sheet (or
      // short-circuits to stub mode when the backend has no keys), and
      // posts the payment back to /unlocks/payment-confirm. We then
      // consume the unlock against this specific matched trip.
      final result = await checkout.pay(user: user);
      switch (result) {
        case UnlockCheckoutSuccess():
          // Same null-tripId branch as the ad path. Pre-trip mode: skip
          // the consume call; next /trips picks up the new Unlock.
          final tid = widget.tripId;
          if (tid != null) {
            await _api.unlockMatchForTrip(tid);
          }
          if (!mounted) return;
          Navigator.of(context).pop(const MatchUnlockedSuccess());
        case UnlockCheckoutCancelled():
          if (!mounted) return;
          setState(() => _paying = false);
        case UnlockCheckoutFailed(:final message):
          if (!mounted) return;
          setState(() {
            _paying = false;
            _error = message;
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = _clean(e);
      });
    } finally {
      checkout.dispose();
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  @override
  Widget build(BuildContext context) {
    final adsDone = _adsWatched >= widget.adsRequired;
    final priceLabel = '₹${(widget.unlockPricePaise / 100).toStringAsFixed(0)}';
    final busy = _adInProgress || _paying;
    // If the SDK never initialised (emulator without Play Services,
    // missing native plugin link, etc.), hide the ads CTA so the
    // rider isn't repeatedly clicking a button that always fails. Pay
    // path becomes the only option until they fix the device.
    final adsAvailable = AdService.instance.isAvailable;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle.
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Match found 🎉',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Unlock to see your co-rider and start coordinating the ride.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 20),

              // Ads option — primary path. Hidden entirely when the
              // SDK couldn't initialise, otherwise we'd dangle a CTA
              // that always errors. Pay path picks up as the default.
              if (adsAvailable) ...[
                _OptionCard(
                  title: adsDone
                      ? 'All ads watched ✓'
                      : 'Watch ${widget.adsRequired} short ads',
                  subtitle:
                      '$_adsWatched of ${widget.adsRequired} ads watched · free',
                  cta: adsDone
                      ? 'Unlocking…'
                      : (_adInProgress ? 'Loading ad…' : 'Watch ad'),
                  primary: true,
                  progress: _adsWatched / widget.adsRequired,
                  onPressed: adsDone || busy ? null : _watchAd,
                ),
                const SizedBox(height: 12),
              ] else ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.black54),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Free-ad path unavailable on this device. '
                          'Use the pay option to unlock.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Pay option — instant unlock.
              _OptionCard(
                title: 'Skip the ads',
                subtitle: 'Pay $priceLabel — instant unlock, no waiting',
                cta: _paying ? 'Processing…' : 'Pay $priceLabel',
                primary: false,
                onPressed: busy || adsDone ? null : _pay,
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: _error!),
              ],

              const SizedBox(height: 12),
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).pop(const MatchUnlockCancelled()),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String cta;
  final bool primary;
  final double? progress;
  final VoidCallback? onPressed;
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.primary,
    required this.onPressed,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: primary ? AppTheme.brandLight : const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary ? AppTheme.brandDark.withValues(alpha: 0.2) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: primary ? AppTheme.brandDark : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: primary ? AppTheme.brandDark : Colors.black54,
              height: 1.35,
            ),
          ),
          if (progress != null && progress! < 1) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.white,
                valueColor:
                    const AlwaysStoppedAnimation(AppTheme.brand),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    primary ? AppTheme.brand : Colors.white,
                foregroundColor:
                    primary ? Colors.white : AppTheme.brandDark,
                elevation: 0,
                side: primary
                    ? BorderSide.none
                    : const BorderSide(color: AppTheme.brand),
              ),
              child: Text(cta),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

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
