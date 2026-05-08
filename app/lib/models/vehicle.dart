/// Vehicle types ShareCab supports for shared rides.
enum VehicleType {
  /// 4-5 seater car (sedan / hatchback). Caps at 3 passengers when shared.
  hatchback,

  /// 4-5 seater car. Same cap as hatchback (3 passengers).
  sedan,

  /// 7 seater SUV / MPV. Caps at 5 passengers when shared.
  suv,
}

extension VehicleTypeMeta on VehicleType {
  String get label {
    switch (this) {
      case VehicleType.hatchback:
        return 'Hatchback';
      case VehicleType.sedan:
        return 'Sedan';
      case VehicleType.suv:
        return 'SUV';
    }
  }

  /// Total physical seats including driver (e.g. 5 = 4 passengers + driver).
  int get totalSeats {
    switch (this) {
      case VehicleType.hatchback:
      case VehicleType.sedan:
        return 5;
      case VehicleType.suv:
        return 7;
    }
  }

  /// Maximum riders allowed when sharing — leaves headroom for luggage.
  /// 4-5 seater → 3 riders, 7 seater → 5 riders.
  int get maxSharedRiders {
    switch (this) {
      case VehicleType.hatchback:
      case VehicleType.sedan:
        return 3;
      case VehicleType.suv:
        return 5;
    }
  }

  /// Total luggage capacity (in luggage-seat units). Used by the matching
  /// engine to decide whether another rider's bags fit.
  int get luggageCapacity {
    switch (this) {
      case VehicleType.hatchback:
        return 2;
      case VehicleType.sedan:
        return 3;
      case VehicleType.suv:
        return 5;
    }
  }
}

class Vehicle {
  final String id;
  final VehicleType type;
  final String model;
  final String plate;
  final String color;

  const Vehicle({
    required this.id,
    required this.type,
    required this.model,
    required this.plate,
    required this.color,
  });

  /// Last 4 digits / chars of the plate. Shown to riders for verification.
  String get plateLast4 =>
      plate.replaceAll(RegExp(r'\s+'), '').toUpperCase().padLeft(4).substring(
            (plate.length > 4 ? plate.length - 4 : 0),
          );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'model': model,
        'plate': plate,
        'color': color,
      };
}
