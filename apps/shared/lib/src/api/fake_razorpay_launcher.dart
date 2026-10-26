import 'dart:async';

import '../models/payment.dart';
import 'payments_api.dart';

/// [RazorpayLauncher] for tests: records the checkout options and resolves
/// with a canned outcome (or waits for [complete] when [manual] is set).
class FakeRazorpayLauncher implements RazorpayLauncher {
  FakeRazorpayLauncher({this.outcome, this.manual = false});

  /// Returned by [checkout] unless [manual].
  RazorpayOutcome? outcome;

  /// Hold the sheet open until [complete] is called (background scenarios).
  bool manual;
  final opened = <RazorpayCheckout>[];
  Completer<RazorpayOutcome>? _pending;

  bool get isOpen => _pending != null && !_pending!.isCompleted;

  @override
  Future<RazorpayOutcome> checkout(RazorpayCheckout options) {
    opened.add(options);
    if (!manual && outcome != null) return Future.value(outcome);
    _pending = Completer<RazorpayOutcome>();
    return _pending!.future;
  }

  /// Finishes a [manual] checkout.
  void complete(RazorpayOutcome o) {
    if (isOpen) _pending!.complete(o);
  }

  /// A success with Razorpay-shaped ids for [orderId].
  static RazorpaySuccess success(String orderId) => RazorpaySuccess(RazorpayResult(
        paymentId: 'pay_${orderId.replaceFirst('order_', '')}',
        orderId: orderId,
        signature: 'sig_${'f' * 60}',
      ));
}
