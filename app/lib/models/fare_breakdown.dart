/// Structured fare breakdown returned by the backend's `fareService.quoteSolo`
/// / `quoteShared`. The wire format is **paise** for all amounts (matches
/// Razorpay's amount field — 1 INR = 100 paise).
///
/// Use [rupees] getters for display. The raw `*Paise` fields are intentionally
/// `int` so we never lose precision to floating point — important for fare
/// comparison and reconciliation.
class FareBreakdown {
  final String vehicleClass;       // 'hatchback' | 'sedan' | 'suv'
  final double distanceKm;
  final int durationMin;
  final double surgeMultiplier;    // 1.0 = no surge
  final int shareCount;

  final int basePaise;
  final int distancePaise;
  final int timePaise;
  final int surgeAdditionPaise;
  final int bookingFeePaise;
  final int gstPaise;

  final int subtotalPaise;
  final int totalPaise;
  final int driverPayoutPaise;
  final bool minimumFareApplied;

  const FareBreakdown({
    required this.vehicleClass,
    required this.distanceKm,
    required this.durationMin,
    required this.surgeMultiplier,
    required this.shareCount,
    required this.basePaise,
    required this.distancePaise,
    required this.timePaise,
    required this.surgeAdditionPaise,
    required this.bookingFeePaise,
    required this.gstPaise,
    required this.subtotalPaise,
    required this.totalPaise,
    required this.driverPayoutPaise,
    required this.minimumFareApplied,
  });

  // Display helpers — rupees as doubles for formatting.
  double get totalRupees => totalPaise / 100;
  double get driverPayoutRupees => driverPayoutPaise / 100;
  double get bookingFeeRupees => bookingFeePaise / 100;
  double get gstRupees => gstPaise / 100;
  double get baseRupees => basePaise / 100;
  double get distanceRupees => distancePaise / 100;
  double get timeRupees => timePaise / 100;
  double get surgeAdditionRupees => surgeAdditionPaise / 100;
  double get subtotalRupees => subtotalPaise / 100;

  bool get isShared => shareCount > 1;
  bool get hasSurge => surgeMultiplier > 1.001;
  bool get hasGst => gstPaise > 0;

  factory FareBreakdown.fromJson(Map<String, dynamic> json) {
    final c = (json['components'] as Map?)?.cast<String, dynamic>() ?? const {};
    int paiseOf(String key, [int fallback = 0]) {
      final v = c[key] ?? json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }
    return FareBreakdown(
      vehicleClass: (json['vehicleClass'] as String?) ?? 'sedan',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      durationMin: (json['durationMin'] as num?)?.toInt() ?? 0,
      surgeMultiplier: (json['surgeMultiplier'] as num?)?.toDouble() ?? 1.0,
      shareCount: (json['shareCount'] as num?)?.toInt() ?? 1,
      basePaise: paiseOf('base'),
      distancePaise: paiseOf('distance'),
      timePaise: paiseOf('time'),
      surgeAdditionPaise: paiseOf('surgeAddition'),
      bookingFeePaise: paiseOf('bookingFee'),
      gstPaise: paiseOf('gst'),
      subtotalPaise: (json['subtotal'] as num?)?.toInt() ?? 0,
      totalPaise: (json['total'] as num?)?.toInt() ?? 0,
      driverPayoutPaise: (json['driverPayout'] as num?)?.toInt() ?? 0,
      minimumFareApplied: json['minimumFareApplied'] == true,
    );
  }
}
