import 'place.dart';
import 'vehicle.dart';

/// Subscription view exposed by `GET /api/drivers/me` (and the more focused
/// `GET /api/drivers/me/subscription`). The backend computes `isSubscribed`
/// from `expiresAt > now` so we don't have to repeat the math here.
class DriverSubscription {
  final bool isSubscribed;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final String? paymentRef;

  const DriverSubscription({
    required this.isSubscribed,
    this.startedAt,
    this.expiresAt,
    this.paymentRef,
  });

  bool get isFreeTrial =>
      paymentRef == 'free-trial' || paymentRef == 'free-trial-backfill';

  /// Days until expiry, ceil — so a sub expiring in 12 hours shows "1 day left".
  int? get daysLeft {
    final exp = expiresAt;
    if (exp == null) return null;
    final ms = exp.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / (24 * 60 * 60 * 1000)).ceil();
  }

  factory DriverSubscription.fromJson(Map<String, dynamic> json) {
    return DriverSubscription(
      isSubscribed: json['isSubscribed'] as bool? ?? false,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      paymentRef: json['paymentRef'] as String?,
    );
  }
}

/// Full driver-side profile used by HomeScreen + ActiveTripScreen. Mirrors
/// the backend `GET /api/drivers/me` response.
class DriverProfile {
  final String id;
  final String userId;
  final String licenseNumber;
  final Vehicle vehicle;
  final bool isOnline;
  final List<String> activeTripIds;
  final Place? currentLocation;
  final DriverSubscription subscription;

  /// Manual verification gate — 'pending' until ops approves the docs,
  /// 'approved' lets the driver reach the home dashboard + online toggle.
  /// Unique to the driver app (the rider app's DriverProfile mirror omits
  /// this since riders only ever see approved drivers).
  final String verificationStatus;

  const DriverProfile({
    required this.id,
    required this.userId,
    required this.licenseNumber,
    required this.vehicle,
    required this.isOnline,
    required this.activeTripIds,
    required this.subscription,
    required this.verificationStatus,
    this.currentLocation,
  });

  bool get hasActiveDispatch => activeTripIds.isNotEmpty;

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final v = (json['vehicle'] as Map<String, dynamic>?) ?? const {};
    final loc = json['currentLocation'] as Map<String, dynamic>?;
    Place? location;
    if (loc != null) {
      try {
        location = Place.fromJson({
          'address': '',
          'location': loc,
        });
      } catch (_) {
        location = null;
      }
    }
    return DriverProfile(
      id: (json['_id'] as String?) ?? '',
      userId: (json['user'] as String?) ?? '',
      licenseNumber: (json['licenseNumber'] as String?) ?? '',
      vehicle: Vehicle(
        id: (json['_id'] as String?) ?? '',
        type: _vehicleTypeFromCapacity(v['capacity'] as num?),
        model: (v['model'] as String?) ?? '',
        plate: (v['plate'] as String?) ?? '',
        color: (v['color'] as String?) ?? '',
      ),
      isOnline: json['isOnline'] as bool? ?? false,
      activeTripIds: ((json['activeTrips'] as List?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      currentLocation: location,
      subscription: DriverSubscription.fromJson(
        (json['subscription'] as Map<String, dynamic>?) ?? const {},
      ),
      verificationStatus:
          (json['verificationStatus']?.toString() ?? 'pending'),
    );
  }
}

VehicleType _vehicleTypeFromCapacity(num? capacity) {
  final c = capacity?.toInt() ?? 4;
  if (c >= 6) return VehicleType.suv;
  if (c >= 4) return VehicleType.sedan;
  return VehicleType.hatchback;
}

/// Razorpay order handed back from `POST /api/drivers/subscribe`. The
/// driver app feeds these straight into checkout.js. When [razorpayKeyId]
/// is empty, the backend is running without keys (stub mode) — the app
/// should skip the checkout sheet and confirm with a fake paymentRef so
/// local demos still exercise the full flow.
class SubscriptionOrder {
  final String orderId;
  final int amountPaise;
  final String currency;
  final String razorpayKeyId;

  const SubscriptionOrder({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.razorpayKeyId,
  });

  bool get isStub => razorpayKeyId.isEmpty;

  factory SubscriptionOrder.fromJson(Map<String, dynamic> json) {
    return SubscriptionOrder(
      orderId: (json['orderId'] as String?) ?? '',
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?) ?? 'INR',
      razorpayKeyId: (json['razorpayKeyId'] as String?) ?? '',
    );
  }
}
