import '../models/payment.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// SPEC §15 rider payment endpoints. Throws [ApiException] on failure.
class PaymentsApi {
  PaymentsApi(this._client);

  final ApiClient _client;

  /// `POST /rides/:id/payment/order`. 409 `RIDE_NOT_PAYABLE` both when the
  /// trip is not COMPLETED yet and when it is already paid (the message
  /// differs), 503 `PAYMENTS_UNAVAILABLE` (gateway not configured — the rider
  /// pays cash instead).
  Future<PaymentOrder> createOrder(String rideId) => guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>('/rides/$rideId/payment/order');
        return PaymentOrder.fromJson(res.data!);
      });

  /// `POST /rides/:id/payment/verify`. 422 `ORDER_MISMATCH`, 400 `SIGNATURE_INVALID`.
  Future<PaymentRecord> verify(String rideId, RazorpayResult result) => guardApi(() async {
        final res = await _client.dio
            .post<Map<String, dynamic>>('/rides/$rideId/payment/verify', data: result.toJson());
        return PaymentRecord.fromJson(res.data!);
      });
}

/// What the app passes to Razorpay Checkout (SPEC §15 step 2).
class RazorpayCheckout {
  const RazorpayCheckout({
    required this.order,
    required this.contact,
    required this.name,
    required this.description,
    this.email,
    this.timeoutSeconds = 300,
  });

  final PaymentOrder order;

  /// Rider phone, E.164, for `prefill.contact`.
  final String contact;

  /// Merchant name shown on the sheet.
  final String name;
  final String description;
  final String? email;
  final int timeoutSeconds;

  /// Options map in the shape `razorpay_flutter` expects.
  Map<String, dynamic> toOptions() => {
        'key': order.keyId,
        'order_id': order.razorpayOrderId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'name': name,
        'description': description,
        'timeout': timeoutSeconds,
        'prefill': {'contact': contact, 'email': ?email},
        'retry': {'enabled': false},
      };
}

/// Why checkout did not produce a payment.
enum RazorpayFailureKind { cancelled, network, error }

/// Outcome of one Checkout session.
sealed class RazorpayOutcome {
  const RazorpayOutcome();
}

class RazorpaySuccess extends RazorpayOutcome {
  const RazorpaySuccess(this.result);

  final RazorpayResult result;
}

class RazorpayFailure extends RazorpayOutcome {
  const RazorpayFailure(this.kind, {this.message});

  final RazorpayFailureKind kind;
  final String? message;

  bool get cancelled => kind == RazorpayFailureKind.cancelled;
}

/// Opens Razorpay Checkout and resolves with the outcome. The rider app
/// wires `razorpay_flutter`; tests use a fake.
abstract class RazorpayLauncher {
  Future<RazorpayOutcome> checkout(RazorpayCheckout options);
}
