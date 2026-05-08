import '../../models/luggage.dart';

/// Single source of truth for the luggage seat math.
///
/// Rules from the product brief:
///   - Handbag / laptop bag                    → 0 luggage seats
///   - 2 regular trolleys                      → 1 luggage seat
///   - 2 big trolleys + 1 small trolley (3 heavy items roughly) → 2 luggage seats
///
/// We generalize that to:
///   light trolley count divided by 2 (rounded up) → light seats
///   heavy trolley count                           → heavy seats
///   total = light seats + heavy seats, capped at 0..N
class LuggageRules {
  const LuggageRules._();

  static int seatsConsumed(LuggageProfile profile) {
    final lightSeats = (profile.trolleyLightCount / 2).ceil();
    final heavySeats = profile.trolleyHeavyCount; // each heavy ≈ 1 seat
    final total = lightSeats + heavySeats;
    return total < 0 ? 0 : total;
  }

  /// Combine multiple riders' luggage into one consumed-seat figure.
  static int totalSeatsConsumed(Iterable<LuggageProfile> profiles) {
    var sum = 0;
    for (final p in profiles) {
      sum += seatsConsumed(p);
    }
    return sum;
  }

  /// Human-readable summary like "2 cabin bags · 1 large bag".
  /// Used in the match-result and luggage-screen review states.
  static String describe(LuggageProfile p) {
    final parts = <String>[];
    if (p.handbagCount > 0) {
      parts.add(_count(p.handbagCount, 'handbag', 'handbags'));
    }
    if (p.trolleyLightCount > 0) {
      parts.add(_count(p.trolleyLightCount, 'cabin bag', 'cabin bags'));
    }
    if (p.trolleyHeavyCount > 0) {
      parts.add(_count(p.trolleyHeavyCount, 'large bag', 'large bags'));
    }
    if (parts.isEmpty) return 'No luggage';
    return parts.join(' · ');
  }

  static String _count(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';
}
