/// Payment models (SPEC §15, §8 `payment:status`).
library;

import 'json.dart';
import 'receipt.dart';

/// `POST /rides/:id/payment/order`: what Razorpay Checkout needs.
class PaymentOrder {
  const PaymentOrder({
    required this.razorpayOrderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
  });

  factory PaymentOrder.fromJson(Map<String, dynamic> json) => PaymentOrder(
        razorpayOrderId: json['razorpay_order_id'] as String,
        amountPaise: asInt(json['amount']) ?? 0,
        currency: json['currency'] as String? ?? 'INR',
        keyId: json['key_id'] as String? ?? '',
      );

  final String razorpayOrderId;

  /// Amount in paise (₹118 → 11800).
  final int amountPaise;
  final String currency;
  final String keyId;

  double get amountRupees => amountPaise / 100;
}

/// The three fields Razorpay Checkout returns on success, posted to
/// `/payment/verify`.
class RazorpayResult {
  const RazorpayResult({
    required this.paymentId,
    required this.orderId,
    required this.signature,
  });

  final String paymentId;
  final String orderId;
  final String signature;

  Map<String, dynamic> toJson() => {
        'razorpay_payment_id': paymentId,
        'razorpay_order_id': orderId,
        'razorpay_signature': signature,
      };
}

/// `payments` row as returned by `/payment/verify`.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.rideId,
    required this.method,
    required this.amount,
    required this.status,
    this.gatewayOrderId,
    this.gatewayPaymentId,
    this.paidAt,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        id: json['id'] as String,
        rideId: json['ride_id'] as String,
        method: json['method'] as String? ?? '',
        amount: asDouble(json['amount']) ?? 0,
        status: PaymentStatus.fromWire(json['status']),
        gatewayOrderId: json['gateway_order_id'] as String?,
        gatewayPaymentId: json['gateway_payment_id'] as String?,
        paidAt: asInstant(json['paid_at']),
      );

  final String id;
  final String rideId;

  /// `cash`, `upi`, `card`, `wallet`.
  final String method;
  final double amount;
  final PaymentStatus status;
  final String? gatewayOrderId;
  final String? gatewayPaymentId;
  final DateTime? paidAt;
}

/// `payment:status {ride_id, status: 'paid' | 'failed', method}` (SPEC §8),
/// sent to both parties. `paid` also moves the ride to PAID.
class PaymentStatusEvent {
  const PaymentStatusEvent({required this.rideId, required this.status, required this.method});

  factory PaymentStatusEvent.fromJson(Map<String, dynamic> json) => PaymentStatusEvent(
        rideId: json['ride_id'] as String,
        status: PaymentStatus.fromWire(json['status']),
        method: json['method'] as String? ?? '',
      );

  final String rideId;
  final PaymentStatus status;
  final String method;

  bool get isPaid => status == PaymentStatus.paid;
  bool get isCash => method == 'cash';
}

/// `POST /rides/:id/rating` / `POST /driver/rides/:id/rating` response.
class RatingResult {
  const RatingResult({required this.id, required this.rideId, required this.stars, this.comment});

  factory RatingResult.fromJson(Map<String, dynamic> json) => RatingResult(
        id: json['id'] as String,
        rideId: json['ride_id'] as String,
        stars: asInt(json['stars']) ?? 0,
        comment: json['comment'] as String?,
      );

  final String id;
  final String rideId;
  final int stars;
  final String? comment;
}
