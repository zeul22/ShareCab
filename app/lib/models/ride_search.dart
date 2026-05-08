import 'luggage.dart';
import 'place.dart';
import 'vehicle.dart';

enum MatchPreference {
  /// Find passengers whose drop-off is within 2-4 km of the user's drop-off.
  destinationNearby,

  /// Auto-allocate to any compatible passenger/group meeting all
  /// hard constraints (route, luggage, capacity, timing).
  randomCompatible,
}

/// A user's in-progress ride search. Holds everything the matching engine
/// needs to find a compatible group.
class RideSearch {
  final Place? pickup;
  final Place? dropoff;
  final LuggageProfile luggage;
  final MatchPreference preference;

  /// Vehicle preference: null means "any". Hatchback/Sedan caps at 3 riders,
  /// SUV caps at 5.
  final VehicleType? preferredVehicle;

  /// Airport-arrival mode: when true, the search session waits until
  /// [airportLandsAt] before pulling other concurrent riders.
  final bool airportArrivalMode;
  final DateTime? airportLandsAt;

  /// When the session was started — used for the active-window check
  /// (riders within ~10 minutes are considered concurrent).
  final DateTime startedAt;

  const RideSearch({
    this.pickup,
    this.dropoff,
    this.luggage = LuggageProfile.empty,
    this.preference = MatchPreference.destinationNearby,
    this.preferredVehicle,
    this.airportArrivalMode = false,
    this.airportLandsAt,
    required this.startedAt,
  });

  bool get isReadyToSearch => pickup != null && dropoff != null;

  RideSearch copyWith({
    Place? pickup,
    Place? dropoff,
    LuggageProfile? luggage,
    MatchPreference? preference,
    VehicleType? preferredVehicle,
    bool? airportArrivalMode,
    DateTime? airportLandsAt,
    DateTime? startedAt,
    bool clearPreferredVehicle = false,
    bool clearAirportLandsAt = false,
  }) {
    return RideSearch(
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      luggage: luggage ?? this.luggage,
      preference: preference ?? this.preference,
      preferredVehicle:
          clearPreferredVehicle ? null : (preferredVehicle ?? this.preferredVehicle),
      airportArrivalMode: airportArrivalMode ?? this.airportArrivalMode,
      airportLandsAt:
          clearAirportLandsAt ? null : (airportLandsAt ?? this.airportLandsAt),
      startedAt: startedAt ?? this.startedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'pickup': pickup?.toJson(),
        'dropoff': dropoff?.toJson(),
        'luggage': luggage.toJson(),
        'preference': preference.name,
        'preferredVehicle': preferredVehicle?.name,
        'airportArrivalMode': airportArrivalMode,
        'airportLandsAt': airportLandsAt?.toIso8601String(),
        'startedAt': startedAt.toIso8601String(),
      };
}
