import '../../models/vehicle.dart';

/// Vehicle capacity rules — kept in one place so the matching engine and the
/// UI can both ask the same questions.
///
/// Rider caps come from the product brief:
///   - 4-5 seater (hatchback/sedan) → max 3 shared riders
///   - 7 seater (SUV)               → max 5 shared riders
///
/// These are intentionally lower than the physical seat count so there is
/// space for luggage.
class VehicleRules {
  const VehicleRules._();

  /// Pick the smallest vehicle type that fits [riders] passengers AND has
  /// enough luggage capacity for [luggageSeats]. Returns null if no supported
  /// vehicle works (caller should retry without that rider).
  static VehicleType? smallestThatFits({
    required int riders,
    required int luggageSeats,
  }) {
    for (final type in VehicleType.values) {
      if (riders <= type.maxSharedRiders && luggageSeats <= type.luggageCapacity) {
        return type;
      }
    }
    return null;
  }

  /// True if a given vehicle type can fit [riders] passengers and [luggageSeats]
  /// of luggage.
  static bool fits(VehicleType type, {required int riders, required int luggageSeats}) {
    return riders <= type.maxSharedRiders && luggageSeats <= type.luggageCapacity;
  }
}
