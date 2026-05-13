import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pending_co_rider_rating.dart';
import '../services/api/ride_api.dart';
import '../theme/app_theme.dart';

/// Outcome of [CoRiderRatingDialog.show]. The caller dequeues the
/// prompt regardless — only the recompute side effect differs.
enum CoRiderRatingOutcome {
  /// User submitted a star rating. The target's User.rating recomputes.
  rated,

  /// User explicitly tapped Skip. A -0.25 penalty was applied to THEIR
  /// rating (not the target's). Floored at 1.0.
  skipped,

  /// User dismissed without choosing (back gesture, etc.). No write.
  /// The prompt will reappear on the next `getPendingCoRiderRatings`
  /// tick so the user has to make an explicit choice eventually.
  dismissed,
}

/// Modal that prompts the rider to rate a co-rider after their leg
/// has completed. Owns its own submit / error / loading state so a
/// failed network call doesn't dismiss the dialog (mirrors the
/// driver-side pickup OTP dialog pattern).
class CoRiderRatingDialog extends StatefulWidget {
  final PendingCoRiderRating pending;

  const CoRiderRatingDialog({super.key, required this.pending});

  /// Pops the dialog over [context] and resolves to the [CoRiderRatingOutcome]
  /// the user produced. Non-dismissible: dismissing via back gesture
  /// also resolves to [CoRiderRatingOutcome.dismissed].
  static Future<CoRiderRatingOutcome> show(
    BuildContext context, {
    required PendingCoRiderRating pending,
  }) async {
    final result = await showDialog<CoRiderRatingOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CoRiderRatingDialog(pending: pending),
    );
    return result ?? CoRiderRatingOutcome.dismissed;
  }

  @override
  State<CoRiderRatingDialog> createState() => _CoRiderRatingDialogState();
}

class _CoRiderRatingDialogState extends State<CoRiderRatingDialog> {
  /// 0 = nothing picked yet, 1-5 = stars. Submit is disabled at 0.
  int _stars = 0;
  bool _busy = false;
  String? _error;

  Future<void> _submitRating() async {
    if (_stars < 1 || _stars > 5) {
      setState(() => _error = 'Pick a star rating, or tap Skip.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<RideApi>();
      await api.rateCoRider(
        tripId: widget.pending.tripId,
        coRiderUserId: widget.pending.coRiderId,
        stars: _stars,
      );
      if (!mounted) return;
      Navigator.of(context).pop(CoRiderRatingOutcome.rated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  Future<void> _skip() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<RideApi>();
      await api.skipCoRiderRating(
        tripId: widget.pending.tripId,
        coRiderUserId: widget.pending.coRiderId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(CoRiderRatingOutcome.skipped);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    return AlertDialog(
      title: Text('Rate ${p.coRiderName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current rating: ${p.coRiderRating.toStringAsFixed(2)}★',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Star picker. Tap a star to set 1-5; tap the same star
          // again to clear back to 0 (lets a user undo before submit).
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return IconButton(
                iconSize: 32,
                onPressed: _busy ? null : () {
                  setState(() {
                    _stars = (_stars == i + 1) ? 0 : (i + 1);
                    _error = null;
                  });
                },
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: filled ? Colors.amber.shade700 : Colors.black38,
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          // Penalty warning. Explicit number + direction so the user
          // can make an informed choice. Mirrored exactly by the
          // backend's -0.25 deduction in skipRating.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE6C57F)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFB47700), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Skipping reduces YOUR rating by 0.25 stars '
                    '(floor 1.0). Rating your co-rider keeps yours intact.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Colors.red.shade800, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _skip,
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Skip (-0.25)'),
        ),
        ElevatedButton(
          onPressed: _busy || _stars == 0 ? null : _submitRating,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.brand,
            foregroundColor: Colors.white,
          ),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(_stars == 0 ? 'Rate' : 'Submit $_stars★'),
        ),
      ],
    );
  }
}
