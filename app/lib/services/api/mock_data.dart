import 'dart:math';

import '../../models/driver.dart';
import '../../models/luggage.dart';
import '../../models/passenger.dart';
import '../../models/place.dart';
import '../../models/vehicle.dart';

/// Static fixtures the mock API draws from. Replace with real backend calls
/// when the API is ready (see `RideApi`).
class MockData {
  const MockData._();

  // City anchor used to position synthetic drivers/passengers around the user.
  // Defaults to Connaught Place, Delhi.
  static const Place _anchor = Place(
    address: 'Connaught Place, New Delhi',
    lat: 28.6315,
    lng: 77.2167,
  );

  /// Pool of currently-searching co-passengers. The matching engine receives
  /// this list and filters/sequences from it. Geographically clustered so
  /// matches actually trigger.
  static List<Passenger> activeSearchPool() {
    return [
      Passenger(
        id: 'pax_aarav',
        firstName: 'Aarav',
        rating: 4.9,
        pickup: _shifted(_anchor, 0.6, -0.3),
        dropoff: _shifted(_anchor, 6.2, 1.1),
        luggage: const LuggageProfile(handbagCount: 1, trolleyLightCount: 1),
      ),
      Passenger(
        id: 'pax_priya',
        firstName: 'Priya',
        rating: 4.8,
        pickup: _shifted(_anchor, 0.9, 0.4),
        dropoff: _shifted(_anchor, 6.6, 0.7),
        luggage: const LuggageProfile(trolleyLightCount: 2),
      ),
      Passenger(
        id: 'pax_rohan',
        firstName: 'Rohan',
        rating: 4.7,
        pickup: _shifted(_anchor, -0.5, 0.8),
        dropoff: _shifted(_anchor, 7.3, -0.4),
        luggage: const LuggageProfile(handbagCount: 1),
      ),
      Passenger(
        id: 'pax_sneha',
        firstName: 'Sneha',
        rating: 5.0,
        pickup: _shifted(_anchor, 1.1, -0.7),
        dropoff: _shifted(_anchor, 5.8, 1.6),
        luggage: const LuggageProfile(trolleyHeavyCount: 1, trolleyLightCount: 1),
      ),
      Passenger(
        id: 'pax_kabir',
        firstName: 'Kabir',
        rating: 4.6,
        pickup: _shifted(_anchor, 0.3, 1.2),
        dropoff: _shifted(_anchor, 9.5, 4.0), // intentionally far — random-only candidate
        luggage: const LuggageProfile(handbagCount: 2, trolleyLightCount: 1),
      ),
    ];
  }

  static List<Driver> driverPool() {
    return [
      const Driver(
        id: 'drv_ravi',
        name: 'Ravi Sharma',
        phoneMasked: '98••••3456',
        rating: 4.9,
        totalRides: 2871,
        vehicle: Vehicle(
          id: 'veh_dl3cab1234',
          type: VehicleType.sedan,
          model: 'Maruti Dzire',
          plate: 'DL3CAB1234',
          color: 'White',
        ),
      ),
      const Driver(
        id: 'drv_anil',
        name: 'Anil Kumar',
        phoneMasked: '97••••8800',
        rating: 4.8,
        totalRides: 1942,
        vehicle: Vehicle(
          id: 'veh_dl9ab7799',
          type: VehicleType.suv,
          model: 'Toyota Innova',
          plate: 'DL9AB7799',
          color: 'Silver',
        ),
      ),
      const Driver(
        id: 'drv_meera',
        name: 'Meera Joshi',
        phoneMasked: '95••••2210',
        rating: 5.0,
        totalRides: 612,
        vehicle: Vehicle(
          id: 'veh_dl1zx5566',
          type: VehicleType.hatchback,
          model: 'Hyundai i20',
          plate: 'DL1ZX5566',
          color: 'Blue',
        ),
      ),
    ];
  }

  /// Pick the driver that fits the proposed vehicle type. Falls back to the
  /// first driver if nothing matches (simulating a dispatch fallback).
  static Driver pickDriverForType(VehicleType type) {
    final pool = driverPool();
    final match = pool.where((d) => d.vehicle.type == type);
    return match.isNotEmpty ? match.first : pool.first;
  }

  /// Generate a 4-digit OTP. Not cryptographically secure — fine for a mock.
  static String generateOtp([Random? rng]) {
    final r = rng ?? Random();
    final n = r.nextInt(10000);
    return n.toString().padLeft(4, '0');
  }

  // ---------------------------------------------------------------------------

  /// Returns a place shifted from [base] by approximately the given km offsets.
  /// Roughly accurate at mid-latitudes; good enough for fixtures.
  static Place _shifted(Place base, double dxKm, double dyKm) {
    const kmPerDegreeLat = 111.0;
    final kmPerDegreeLng = 111.0 * cosDeg(base.lat);
    return Place(
      address: base.address,
      lat: base.lat + dyKm / kmPerDegreeLat,
      lng: base.lng + dxKm / kmPerDegreeLng,
    );
  }
}

double cosDeg(double deg) => cos(deg * pi / 180);
