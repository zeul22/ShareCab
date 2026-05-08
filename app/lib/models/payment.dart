enum PaymentTiming { beforeRide, afterRide }

enum PaymentMethod { upi, card, cash, wallet }

enum PaymentStatus { pending, paid, failed }

/// One rider's payment for a ride. Each rider pays their own share, so a
/// shared ride produces N payments — one per rider.
class Payment {
  final String id;
  final String rideId;
  final String riderUserId;
  final double amount; // INR
  final PaymentTiming timing;
  final PaymentMethod method;
  final PaymentStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;

  const Payment({
    required this.id,
    required this.rideId,
    required this.riderUserId,
    required this.amount,
    required this.timing,
    required this.method,
    required this.status,
    required this.createdAt,
    this.paidAt,
  });

  Payment copyWith({PaymentStatus? status, DateTime? paidAt, PaymentMethod? method}) =>
      Payment(
        id: id,
        rideId: rideId,
        riderUserId: riderUserId,
        amount: amount,
        timing: timing,
        method: method ?? this.method,
        status: status ?? this.status,
        createdAt: createdAt,
        paidAt: paidAt ?? this.paidAt,
      );
}
