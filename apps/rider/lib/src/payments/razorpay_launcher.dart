import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:ride_shared/ride_shared.dart';

/// [RazorpayLauncher] backed by `razorpay_flutter` (SPEC §15 step 2). One
/// Checkout session per call; the SDK re-delivers a result that arrived
/// while the app was in the background (`resync`), and the server's
/// `payment:status` covers the case where the app was killed meanwhile.
class RazorpayFlutterLauncher implements RazorpayLauncher {
  @override
  Future<RazorpayOutcome> checkout(RazorpayCheckout options) {
    final razorpay = Razorpay();
    final completer = Completer<RazorpayOutcome>();

    void finish(RazorpayOutcome outcome) {
      if (!completer.isCompleted) completer.complete(outcome);
      razorpay.clear();
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final paymentId = r.paymentId;
      final orderId = r.orderId ?? options.order.razorpayOrderId;
      final signature = r.signature;
      if (paymentId == null || signature == null) {
        finish(const RazorpayFailure(RazorpayFailureKind.error, message: 'Incomplete payment response'));
        return;
      }
      finish(RazorpaySuccess(RazorpayResult(paymentId: paymentId, orderId: orderId, signature: signature)));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      final kind = switch (r.code) {
        Razorpay.PAYMENT_CANCELLED => RazorpayFailureKind.cancelled,
        Razorpay.NETWORK_ERROR || Razorpay.TLS_ERROR => RazorpayFailureKind.network,
        _ => RazorpayFailureKind.error,
      };
      finish(RazorpayFailure(kind, message: r.message));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      // Not offered in the options; treat as "nothing paid".
      finish(RazorpayFailure(RazorpayFailureKind.error, message: 'Wallet ${r.walletName ?? ''} not supported'));
    });
    try {
      razorpay.open(options.toOptions());
    } catch (e) {
      debugPrint('Razorpay open failed: $e');
      finish(RazorpayFailure(RazorpayFailureKind.error, message: e.toString()));
    }
    return completer.future;
  }
}
