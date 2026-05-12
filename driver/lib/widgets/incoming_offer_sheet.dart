import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip_offer.dart';
import '../services/offer_alert.dart';
import '../theme/app_theme.dart';

/// Outcome of [IncomingOfferSheet.show]. The home screen pattern-matches:
///   - [accepted] → call DriverApi.acceptOffer + wait for next poll → ActiveTrip
///   - [rejected] → call DriverApi.rejectOffer (backend re-dispatches)
///   - [expired]  → backend has already auto-rejected; nothing for client to do
sealed class OfferResult {
  const OfferResult();
}
class OfferAccepted extends OfferResult { const OfferAccepted(); }
class OfferRejected extends OfferResult { const OfferRejected(); }
class OfferExpired  extends OfferResult { const OfferExpired();  }

/// Bottom modal that surfaces a pending dispatch offer. Non-dismissible —
/// the driver MUST tap Accept / Reject (or let the countdown run out).
/// Mirrors Uber/Ola's incoming-ride card.
///
/// The countdown runs locally and auto-closes with [OfferExpired] when
/// it hits zero. The backend's offer-expiry timer fires at the same
/// `expiresAt`, so the two sides agree without explicit sync.
class IncomingOfferSheet extends StatefulWidget {
  final TripOffer offer;

  const IncomingOfferSheet({super.key, required this.offer});

  /// Convenience launcher. Returns the outcome so the caller doesn't have
  /// to handle the showModalBottomSheet plumbing.
  static Future<OfferResult> show(BuildContext context, TripOffer offer) async {
    final result = await showModalBottomSheet<OfferResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => IncomingOfferSheet(offer: offer),
    );
    return result ?? const OfferExpired();
  }

  @override
  State<IncomingOfferSheet> createState() => _IncomingOfferSheetState();
}

class _IncomingOfferSheetState extends State<IncomingOfferSheet> {
  late int _secondsLeft;
  Timer? _timer;
  // Total offer duration — for the progress ring fraction. Captured once
  // on first frame so the visual stays consistent if expiresAt mutates.
  late final int _totalSeconds;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.offer.secondsRemaining();
    _totalSeconds = _secondsLeft <= 0 ? 15 : _secondsLeft;
    // Triple-pulse alert + haptic so the driver actually notices the
    // offer when they're not staring at the screen. Stopped in dispose
    // so late pulses don't fire after accept/reject. See OfferAlert.
    OfferAlert.play();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = widget.offer.secondsRemaining();
      setState(() => _secondsLeft = next);
      if (next <= 0) {
        _timer?.cancel();
        // Pop with Expired only if we're still on screen. The home
        // screen might have stopped the sheet via its own poll if the
        // backend re-dispatched (rejectOffer fired elsewhere).
        if (mounted) Navigator.of(context).pop(const OfferExpired());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Cancel any pending alert pulses — without this, the driver
    // hears beep-3 a second after they've already tapped Accept.
    OfferAlert.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final ringFraction =
        (_totalSeconds == 0) ? 0.0 : (_secondsLeft / _totalSeconds).clamp(0.0, 1.0);
    final isShared = o.groupSize > 1;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle (decorative — sheet is non-dismissible).
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header row — countdown ring + offer headline.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background ring (full circle, faint).
                      const SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 5,
                          valueColor: AlwaysStoppedAnimation(
                            Color(0xFFE3E7EA),
                          ),
                        ),
                      ),
                      // Foreground ring — shrinks as time runs out.
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: ringFraction,
                          strokeWidth: 5,
                          valueColor:
                              const AlwaysStoppedAnimation(AppTheme.brand),
                        ),
                      ),
                      Text(
                        '$_secondsLeft',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brandDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'INCOMING TRIP',
                        style: TextStyle(
                          color: AppTheme.brandDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isShared
                            ? '${o.groupSize} riders sharing'
                            : o.riderName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            o.riderRating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '₹${o.fareEstimateRupees.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppTheme.brand,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),

            // Pickup + dropoff rows.
            _LocationRow(
              dotColor: AppTheme.brand,
              label: 'PICKUP',
              address: o.pickup.address,
            ),
            _LocationRow(
              dotColor: Colors.black87,
              label: 'DROP',
              address: o.dropoff.address,
            ),

            const SizedBox(height: 18),

            // Accept / Reject. Accept is the primary CTA (big + green);
            // Reject is a secondary outlined button next to it.
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _secondsLeft <= 0
                        ? null
                        : () => Navigator.of(context).pop(const OfferRejected()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.warn,
                      side: const BorderSide(color: AppTheme.warn),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _secondsLeft <= 0
                        ? null
                        : () => Navigator.of(context).pop(const OfferAccepted()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'ACCEPT',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final Color dotColor;
  final String label;
  final String address;
  const _LocationRow({
    required this.dotColor,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address.isEmpty ? '(no address)' : address,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
