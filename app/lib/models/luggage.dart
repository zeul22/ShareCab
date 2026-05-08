/// Per-passenger luggage profile.
///
/// Seat-consumption rules from the product brief:
///   - Handbag / laptop bag → 0 seats (carried on lap)
///   - 2 regular trolleys    → 1 luggage seat
///   - More (e.g. 2 big trolleys + 1 small) → 2 luggage seats
///
/// We model the inputs the user enters; the consumed-seat count is derived
/// in [LuggageRules.seatsConsumed] so the rule lives in one place.
enum LuggageSize { none, handbag, trolleyLight, trolleyHeavy }

class LuggageProfile {
  /// Number of personal items that fit on the lap (handbag, laptop bag).
  /// Always counts as 0 luggage seats.
  final int handbagCount;

  /// Number of regular trolley bags (cabin-sized, fits in the boot).
  final int trolleyLightCount;

  /// Number of larger trolleys / suitcases / bulky items.
  final int trolleyHeavyCount;

  const LuggageProfile({
    this.handbagCount = 0,
    this.trolleyLightCount = 0,
    this.trolleyHeavyCount = 0,
  });

  static const empty = LuggageProfile();

  bool get isEmpty =>
      handbagCount == 0 && trolleyLightCount == 0 && trolleyHeavyCount == 0;

  Map<String, dynamic> toJson() => {
        'handbag': handbagCount,
        'trolleyLight': trolleyLightCount,
        'trolleyHeavy': trolleyHeavyCount,
      };

  factory LuggageProfile.fromJson(Map<String, dynamic> json) => LuggageProfile(
        handbagCount: (json['handbag'] ?? 0) as int,
        trolleyLightCount: (json['trolleyLight'] ?? 0) as int,
        trolleyHeavyCount: (json['trolleyHeavy'] ?? 0) as int,
      );

  LuggageProfile copyWith({
    int? handbagCount,
    int? trolleyLightCount,
    int? trolleyHeavyCount,
  }) =>
      LuggageProfile(
        handbagCount: handbagCount ?? this.handbagCount,
        trolleyLightCount: trolleyLightCount ?? this.trolleyLightCount,
        trolleyHeavyCount: trolleyHeavyCount ?? this.trolleyHeavyCount,
      );
}
