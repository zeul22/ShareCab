import 'package:flutter/material.dart';

import '../models/fare_breakdown.dart';
import '../theme/app_theme.dart';

/// Itemised fare card. Shown on the ride confirmation + payment screens.
///
/// Component rows are conditional — surge / GST hide themselves when their
/// values are zero. The total is always rendered and emphasized.
class FareBreakdownCard extends StatelessWidget {
  final FareBreakdown breakdown;

  /// Optional override for the headline above the rows. Defaults to "Fare
  /// breakdown" — the payment screen passes "Amount due" instead.
  final String? title;

  /// Show the trip stats row (vehicle class · km · min) at the top.
  /// Off on the payment screen since it's already shown on the trip card.
  final bool showStats;

  const FareBreakdownCard({
    super.key,
    required this.breakdown,
    this.title,
    this.showStats = true,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[
      _Row('Base fare', breakdown.baseRupees),
      _Row(
        'Distance (${breakdown.distanceKm.toStringAsFixed(1)} km)',
        breakdown.distanceRupees,
      ),
      _Row(
        'Time (${breakdown.durationMin} min)',
        breakdown.timeRupees,
      ),
      if (breakdown.hasSurge)
        _Row(
          'Surge × ${breakdown.surgeMultiplier.toStringAsFixed(2)}',
          breakdown.surgeAdditionRupees,
          color: AppTheme.brandDark,
        ),
      _Row('Booking fee', breakdown.bookingFeeRupees),
      if (breakdown.hasGst)
        _Row('GST (5%)', breakdown.gstRupees),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            (title ?? 'Fare breakdown').toUpperCase(),
            style: const TextStyle(
              color: AppTheme.brandDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          if (showStats) ...[
            const SizedBox(height: 8),
            Text(
              '${_classLabel(breakdown.vehicleClass)} · '
              '${breakdown.distanceKm.toStringAsFixed(1)} km · '
              '${breakdown.durationMin} min'
              '${breakdown.isShared ? ' · shared with ${breakdown.shareCount - 1}' : ''}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          for (final r in rows) _RowView(row: r),
          if (breakdown.minimumFareApplied) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.black54),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Minimum fare applied for this trip distance.',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '₹${breakdown.totalRupees.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppTheme.brand,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _classLabel(String vc) {
    switch (vc) {
      case 'hatchback':
        return 'Hatchback';
      case 'sedan':
        return 'Sedan';
      case 'suv':
        return 'SUV';
      default:
        return vc;
    }
  }
}

class _Row {
  final String label;
  final double rupees;
  final Color? color;
  const _Row(this.label, this.rupees, {this.color});
}

class _RowView extends StatelessWidget {
  final _Row row;
  const _RowView({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: row.color ?? Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '₹${row.rupees.toStringAsFixed(2)}',
            style: TextStyle(
              color: row.color ?? Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
