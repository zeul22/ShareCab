import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../models/driver_profile.dart';
import '../models/user.dart';
import 'api/driver_api.dart';

/// Outcome of [SubscriptionCheckout.renew]. The driver-home screen pattern-
/// matches on this to decide whether to refresh the profile, show a snackbar,
/// or stay quiet (user dismissed the sheet).
sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSuccess extends CheckoutResult {
  final DriverProfile profile;
  const CheckoutSuccess(this.profile);
}

class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

class CheckoutFailed extends CheckoutResult {
  final String message;
  const CheckoutFailed(this.message);
}

/// Wraps the Razorpay checkout sheet + the backend `/subscribe` and
/// `/subscribe/confirm` calls into a single Future-returning helper.
///
/// Flow:
///   1. Ask backend for an order (`POST /drivers/subscribe`).
///   2. If backend is in stub mode (no Razorpay keys), skip the sheet and
///      call `/subscribe/confirm` with a fake paymentRef so local demos
///      still extend the subscription.
///   3. Otherwise open Razorpay checkout, await the success/error event,
///      then confirm with the backend (which verifies the HMAC).
///
/// One [SubscriptionCheckout] per renewal — call [dispose] when done so
/// the underlying `Razorpay` plugin clears its native listeners.
class SubscriptionCheckout {
  final DriverApi _api;
  final Razorpay _razorpay;
  Completer<CheckoutResult>? _completer;
  SubscriptionOrder? _pendingOrder;

  SubscriptionCheckout({required DriverApi api, Razorpay? razorpay})
      : _api = api,
        _razorpay = razorpay ?? Razorpay() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  /// Run the renewal flow end-to-end. Returns once the backend has either
  /// confirmed the new subscription or the user dismissed checkout.
  Future<CheckoutResult> renew({required AppUser user}) async {
    SubscriptionOrder order;
    try {
      order = await _api.startSubscriptionOrder();
    } catch (e) {
      return CheckoutFailed(_clean(e));
    }

    // Stub mode: backend has no Razorpay keys, so there's no real sheet to
    // open. Confirm with a synthetic paymentRef and let the backend extend
    // the subscription as usual — its verifyPaymentSignature is a no-op
    // when keys are missing.
    if (order.isStub) {
      try {
        final profile = await _api.confirmSubscription(
          orderId: order.orderId,
          paymentRef: 'stub_${DateTime.now().millisecondsSinceEpoch}',
          amountPaise: order.amountPaise,
          signature: 'stub',
        );
        return CheckoutSuccess(profile);
      } catch (e) {
        return CheckoutFailed(_clean(e));
      }
    }

    // Real Razorpay path. Persist the order so the success handler knows
    // which orderId/amount to confirm with — Razorpay's success callback
    // gives us the paymentId+signature but we keep the orderId locally.
    _pendingOrder = order;
    _completer = Completer<CheckoutResult>();

    try {
      _razorpay.open({
        'key': order.razorpayKeyId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'order_id': order.orderId,
        'name': 'ShareCab',
        'description': 'Driver subscription · 30 days',
        'prefill': {
          'contact': user.phone,
          'name': user.name,
        },
        'theme': {'color': '#0E8A6E'},
      });
    } catch (e) {
      _completer!.complete(CheckoutFailed(_clean(e)));
    }

    return _completer!.future;
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    final order = _pendingOrder;
    final completer = _completer;
    if (order == null || completer == null || completer.isCompleted) return;

    final paymentId = r.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      completer.complete(const CheckoutFailed('Razorpay returned no paymentId'));
      return;
    }
    try {
      final profile = await _api.confirmSubscription(
        orderId: order.orderId,
        paymentRef: paymentId,
        amountPaise: order.amountPaise,
        signature: r.signature,
      );
      completer.complete(CheckoutSuccess(profile));
    } catch (e) {
      completer.complete(CheckoutFailed(_clean(e)));
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    // Razorpay's `code == Razorpay.NETWORK_ERROR` covers both user-cancel
    // and connectivity drops; we surface the message verbatim so the user
    // can act on it. Empty messages downgrade to a generic notice.
    final msg = (r.message ?? '').trim();
    if (r.code == Razorpay.PAYMENT_CANCELLED || msg.toLowerCase().contains('cancel')) {
      completer.complete(const CheckoutCancelled());
    } else {
      completer.complete(CheckoutFailed(msg.isEmpty ? 'Payment failed' : msg));
    }
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    // External wallets (e.g. Paytm) close checkout without firing a
    // payment-success event. Treat as cancelled — the driver can retry.
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(const CheckoutCancelled());
    }
  }

  void dispose() {
    _razorpay.clear();
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(const CheckoutCancelled());
    }
  }

  static String _clean(Object e) {
    final s = e.toString();
    return s.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  @visibleForTesting
  Razorpay get razorpayForTest => _razorpay;
}
