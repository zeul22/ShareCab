import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../models/user.dart';
import 'api/ride_api.dart';

/// Outcome of [UnlockCheckout.pay]. The caller pattern-matches: on
/// [UnlockCheckoutSuccess], proceed to consume the unlock against the
/// matched trip; on [UnlockCheckoutCancelled], stay on the unlock sheet;
/// on [UnlockCheckoutFailed], surface the message.
sealed class UnlockCheckoutResult {
  const UnlockCheckoutResult();
}

class UnlockCheckoutSuccess extends UnlockCheckoutResult {
  /// Whether the order was created in stub mode (no Razorpay keys on the
  /// backend). The caller still gets a "success" — but only the synthetic
  /// paymentRef was used; no real money moved. Useful for log filtering.
  final bool wasStub;
  const UnlockCheckoutSuccess({this.wasStub = false});
}

class UnlockCheckoutCancelled extends UnlockCheckoutResult {
  const UnlockCheckoutCancelled();
}

class UnlockCheckoutFailed extends UnlockCheckoutResult {
  final String message;
  const UnlockCheckoutFailed(this.message);
}

/// Wraps the Razorpay checkout sheet + the backend `/unlocks/order` and
/// `/unlocks/payment-confirm` calls for the rider unlock pay path.
///
/// Mirrors [SubscriptionCheckout] in shape — the two share the same
/// two-step Razorpay flow with different `notes.kind` tagging. Kept
/// separate to avoid coupling the unlock UX to driver concerns.
///
/// One instance per attempt — call [dispose] when done so the underlying
/// Razorpay plugin clears its native listeners.
class UnlockCheckout {
  final RideApi _api;
  final Razorpay _razorpay;
  Completer<UnlockCheckoutResult>? _completer;
  UnlockOrder? _pendingOrder;

  UnlockCheckout({required RideApi api, Razorpay? razorpay})
      : _api = api,
        _razorpay = razorpay ?? Razorpay() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  /// Run the unlock pay flow end-to-end. Returns once the backend has
  /// minted the Unlock or the user dismissed the sheet. After
  /// [UnlockCheckoutSuccess], the caller should call
  /// `rideApi.unlockMatchForTrip(tripId)` to consume the unlock against
  /// the specific matched trip — this method only handles the payment.
  Future<UnlockCheckoutResult> pay({required AppUser user}) async {
    UnlockOrder order;
    try {
      order = await _api.startUnlockOrder();
    } catch (e) {
      return UnlockCheckoutFailed(_clean(e));
    }

    // Stub mode: backend has no Razorpay keys, so there's no real sheet
    // to open. Confirm with a synthetic paymentRef — the backend's
    // verifyPaymentSignature is a no-op when keys are missing.
    if (order.isStub) {
      try {
        await _api.recordPaymentForUnlock(
          orderId: order.orderId,
          amountPaise: order.amountPaise,
          paymentRef: 'stub_${DateTime.now().millisecondsSinceEpoch}',
          signature: 'stub',
        );
        return const UnlockCheckoutSuccess(wasStub: true);
      } catch (e) {
        return UnlockCheckoutFailed(_clean(e));
      }
    }

    // Real Razorpay path. Persist the order so the success handler knows
    // which orderId/amount to confirm with.
    _pendingOrder = order;
    _completer = Completer<UnlockCheckoutResult>();

    try {
      _razorpay.open({
        'key': order.razorpayKeyId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'order_id': order.orderId,
        'name': 'ShareCab',
        'description': 'Unlock match · ${user.name.isEmpty ? "rider" : user.name}',
        'prefill': {
          'contact': user.phone,
          'name': user.name,
        },
        'theme': {'color': '#1C8852'},
      });
    } catch (e) {
      _completer!.complete(UnlockCheckoutFailed(_clean(e)));
    }

    return _completer!.future;
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    final order = _pendingOrder;
    final completer = _completer;
    if (order == null || completer == null || completer.isCompleted) return;

    final paymentId = r.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      completer.complete(
        const UnlockCheckoutFailed('Razorpay returned no paymentId'),
      );
      return;
    }
    try {
      await _api.recordPaymentForUnlock(
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        paymentRef: paymentId,
        signature: r.signature,
      );
      completer.complete(const UnlockCheckoutSuccess());
    } catch (e) {
      completer.complete(UnlockCheckoutFailed(_clean(e)));
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    final msg = (r.message ?? '').trim();
    if (r.code == Razorpay.PAYMENT_CANCELLED ||
        msg.toLowerCase().contains('cancel')) {
      completer.complete(const UnlockCheckoutCancelled());
    } else {
      completer.complete(UnlockCheckoutFailed(
        msg.isEmpty ? 'Payment failed' : msg,
      ));
    }
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    // External wallets (Paytm, etc.) close checkout without firing a
    // payment-success event. Treat as cancelled — the rider can retry.
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(const UnlockCheckoutCancelled());
    }
  }

  void dispose() {
    _razorpay.clear();
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(const UnlockCheckoutCancelled());
    }
  }

  static String _clean(Object e) {
    final s = e.toString();
    return s.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  @visibleForTesting
  Razorpay get razorpayForTest => _razorpay;
}
