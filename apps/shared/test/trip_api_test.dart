import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:ride_shared/testing.dart';

import 'fake_adapter.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test');
const tokens = AuthTokens(accessToken: 'a1', refreshToken: 'r1');
const rideId = 'b3f00e23-129a-469a-96b3-92466eaaee2e';

ApiClient client(FakeAdapter adapter) =>
    ApiClient(config: config, tokens: MemoryTokenStore(tokens), adapter: adapter);

RideApi api(FakeAdapter adapter) => RideApi(client(adapter));

FakeRoute fromFixture(String name, [int status = 200]) => (status: status, body: fixture(name));

Matcher throwsApi(String code, int status) => throwsA(isA<ApiException>()
    .having((e) => e.code, 'code', code)
    .having((e) => e.statusCode, 'status', status)
    .having((e) => e.message, 'message', isNotEmpty));

void main() {
  group('driver trip endpoints', () {
    test('arrived → ARRIVED; 422 TOO_FAR_FROM_PICKUP keeps the distance message', () async {
      final ok = FakeAdapter((_) => fromFixture('ride_arrived_driver_view.json'));
      final r = await api(ok).driverArrived(rideId, lat: 28.6315, lng: 77.2171);
      expect(r.status, RideStatus.arrived);
      expect(r.rider!.canCall, isTrue);
      expect('${ok.calls.single.method} ${ok.calls.single.path}', 'POST /driver/rides/$rideId/arrived');
      expect(ok.jsonBody(0), {'lat': 28.6315, 'lng': 77.2171});

      final far = FakeAdapter((_) => fromFixture('driver_arrived_too_far_422.json', 422));
      await expectLater(
        api(far).driverArrived(rideId, lat: 28.64, lng: 77.2167),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'TOO_FAR_FROM_PICKUP')
            .having((e) => e.message, 'message', 'You are 945 m from the pickup; get within 300 m')),
      );
    });

    test('start sends the OTP + fix; OTP_INVALID counts attempts; OTP_LOCKED after three', () async {
      final ok = FakeAdapter((_) => fromFixture('ride_started_driver_view.json'));
      final r = await api(ok).driverStart(rideId, otp: '3146', lat: 28.6315, lng: 77.2171);
      expect(r.status, RideStatus.started);
      expect(ok.jsonBody(0), {'otp': '3146', 'lat': 28.6315, 'lng': 77.2171});

      for (final (name, msg) in [
        ('driver_start_otp_invalid_401.json', 'Wrong OTP. 2 attempts left.'),
        ('driver_start_otp_invalid_one_left_401.json', 'Wrong OTP. 1 attempt left.'),
        ('driver_start_otp_invalid_none_left_401.json', 'Wrong OTP. No attempts left.'),
      ]) {
        final bad = FakeAdapter((_) => fromFixture(name, 401));
        await expectLater(
          api(bad).driverStart(rideId, otp: '0000', lat: 1, lng: 2),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'OTP_INVALID')
              .having((e) => e.message, 'message', msg)),
        );
      }
      final locked = FakeAdapter((_) => fromFixture('driver_start_otp_locked_401.json', 401));
      await expectLater(api(locked).driverStart(rideId, otp: '0000', lat: 1, lng: 2),
          throwsApi('OTP_LOCKED', 401));
    });

    test('complete → COMPLETED with fare, fee and amount_due', () async {
      final adapter = FakeAdapter((_) => fromFixture('ride_completed_driver_view.json'));
      final r = await api(adapter).driverComplete(rideId, lat: 28.6129, lng: 77.2295);
      expect(r.status, RideStatus.completed);
      expect(r.finalFare, 88);
      expect(r.amountDue, 118);
      expect(adapter.calls.single.path, '/driver/rides/$rideId/complete');
    });

    test('cancel requires a reason; re-queue vs 409 once STARTED', () async {
      final requeue = FakeAdapter((_) => fromFixture('driver_cancel_requeued.json'));
      final r = await api(requeue).driverCancel(rideId, reason: 'Rider not reachable');
      expect(r.status, RideStatus.requested);
      expect(r.driver, isNull);
      expect(requeue.jsonBody(0), {'reason': 'Rider not reachable'});

      final started = FakeAdapter((_) => fromFixture('driver_cancel_started_409.json', 409));
      await expectLater(api(started).driverCancel(rideId, reason: 'x'), throwsApi('INVALID_TRANSITION', 409));

      final noReason = FakeAdapter((_) => fromFixture('driver_cancel_validation_400.json', 400));
      await expectLater(
        api(noReason).driverCancel(rideId, reason: ''),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'VALIDATION_FAILED')
            .having((e) => e.details, 'details', isNotEmpty)),
      );
    });

    test('cash-collected → PAID; 409 ALREADY_PAID; 409 PAYMENT_PENDING', () async {
      final paid = FakeAdapter((_) => fromFixture('ride_paid_driver_view.json'));
      final r = await api(paid).driverCashCollected(rideId);
      expect(r.status, RideStatus.paid);
      expect(r.paidAt, isNotNull);
      expect(paid.calls.single.path, '/driver/rides/$rideId/cash-collected');

      final again = FakeAdapter((_) => fromFixture('driver_cash_collected_already_paid_409.json', 409));
      await expectLater(api(again).driverCashCollected(rideId), throwsApi('ALREADY_PAID', 409));

      final pending = FakeAdapter((_) => (
            status: 409,
            body: {
              'error': {
                'code': 'PAYMENT_PENDING',
                'message': 'An online payment is in progress. Wait a few minutes before collecting cash.',
              }
            }
          ));
      await expectLater(api(pending).driverCashCollected(rideId), throwsApi('PAYMENT_PENDING', 409));
    });

    test('driver rating 201; history and earnings query parameters', () async {
      final adapter = FakeAdapter((o) => switch (o.path) {
            '/driver/rides/$rideId/rating' => fromFixture('rating_driver_201.json', 201),
            '/driver/rides' => fromFixture('driver_rides_page_small.json'),
            '/driver/earnings' => o.uri.queryParameters['period'] == 'week'
                ? fromFixture('driver_earnings_week.json')
                : fromFixture('driver_earnings_today.json'),
            _ => apiError(404, 'NOT_FOUND', 'nope'),
          });
      final a = api(adapter);
      final rating = await a.driverRate(rideId, stars: 4);
      expect(rating.stars, 4);
      expect(adapter.jsonBody(0), {'stars': 4});

      final page = await a.driverHistory(page: 1, limit: 2);
      expect(page.total, 3);
      expect(adapter.calls[1].uri.queryParameters, {'page': '1', 'limit': '2'});
      final paid = page.data.firstWhere((r) => r.finalFare != null);
      expect(paid.earning!.fare, paid.finalFare);
      expect(paid.earning!.net, closeTo(paid.earning!.fare - paid.earning!.commission - paid.earning!.gst, 0.01));
      expect(page.data.where((r) => r.finalFare == null).every((r) => r.earning == null), isTrue);

      final week = await a.driverEarnings(EarningsPeriod.week);
      expect(week.period, EarningsPeriod.week);
      expect(adapter.calls[2].uri.queryParameters, {'period': 'week'});
      final today = await a.driverEarnings(EarningsPeriod.today);
      expect(today.cashCollected, 118);

      final rated = FakeAdapter((_) => fromFixture('rating_already_rated_409.json', 409));
      await expectLater(api(rated).driverRate(rideId, stars: 5), throwsApi('ALREADY_RATED', 409));
    });
  });

  group('rider trip endpoints', () {
    test('cancel after ARRIVED returns the fee; STARTED → 409', () async {
      final fee = FakeAdapter((_) => fromFixture('ride_cancelled_after_arrived_fee.json'));
      final r = await api(fee).cancel('593b722c-a7ba-496a-afb6-f728ea32e48a', reason: 'Changed plans');
      expect(r.status, RideStatus.cancelled);
      expect(r.cancellationFee, 30);
      final started = FakeAdapter((_) => fromFixture('rides_cancel_started_409.json', 409));
      await expectLater(api(started).cancel(rideId), throwsApi('RIDE_NOT_CANCELLABLE', 409));
    });

    test('history, receipt, rating, sos', () async {
      final adapter = FakeAdapter((o) => switch ('${o.method} ${o.path}') {
            'GET /rides' => fromFixture('rides_page1.json'),
            'GET /rides/$rideId/receipt' => fromFixture('receipt_completed_cash.json'),
            'POST /rides/$rideId/rating' => fromFixture('rating_rider_201.json', 201),
            'POST /rides/$rideId/sos' => fromFixture('sos_rider_201.json', 201),
            _ => apiError(404, 'NOT_FOUND', 'nope'),
          });
      final a = api(adapter);
      final page = await a.history(page: 1, limit: 20);
      expect(page.data, hasLength(6));
      expect(adapter.calls[0].uri.queryParameters, {'page': '1', 'limit': '20'});

      final receipt = await a.receipt(rideId);
      expect(receipt.total, 118);

      final rating = await a.rate(rideId, stars: 5, comment: '  Smooth ride ');
      expect(rating.comment, 'Smooth ride');
      expect(adapter.jsonBody(2), {'stars': 5, 'comment': 'Smooth ride'});
      await a.rate(rideId, stars: 3, comment: '   ');
      expect(adapter.jsonBody(3), {'stars': 3});

      await a.sos(rideId, lat: 28.62, lng: 77.22);
      expect(adapter.jsonBody(4), {'lat': 28.62, 'lng': 77.22});
    });

    test('receipt 409 RECEIPT_NOT_READY; rating 409 RIDE_NOT_RATEABLE / ALREADY_RATED', () async {
      final notReady = FakeAdapter((_) => fromFixture('receipt_not_ready_409.json', 409));
      await expectLater(api(notReady).receipt(rideId), throwsApi('RECEIPT_NOT_READY', 409));
      final notRateable = FakeAdapter((_) => fromFixture('rating_not_rateable_409.json', 409));
      await expectLater(api(notRateable).rate(rideId, stars: 3), throwsApi('RIDE_NOT_RATEABLE', 409));
      final rated = FakeAdapter((_) => fromFixture('rating_already_rated_409.json', 409));
      await expectLater(api(rated).rate(rideId, stars: 3), throwsApi('ALREADY_RATED', 409));
    });
  });

  group('PaymentsApi', () {
    test('createOrder parses the Razorpay order; verify posts the three fields', () async {
      final adapter = FakeAdapter((o) => o.path.endsWith('/order')
          ? (status: 200, body: {'razorpay_order_id': 'order_Nx1', 'amount': 11800, 'currency': 'INR', 'key_id': 'rzp_test_k'})
          : (status: 200, body: {
              'id': 'p1',
              'ride_id': rideId,
              'method': 'upi',
              'amount': 118,
              'status': 'paid',
              'gateway_order_id': 'order_Nx1',
              'gateway_payment_id': 'pay_1',
              'paid_at': '2026-10-04T06:39:01.794Z',
              'created_at': '2026-10-04T06:38:01.794Z',
            }));
      final p = PaymentsApi(client(adapter));
      final order = await p.createOrder(rideId);
      expect(order.razorpayOrderId, 'order_Nx1');
      expect(order.amountPaise, 11800);
      expect(order.keyId, 'rzp_test_k');
      expect('${adapter.calls[0].method} ${adapter.calls[0].path}', 'POST /rides/$rideId/payment/order');

      final rec = await p.verify(rideId, const RazorpayResult(paymentId: 'pay_1', orderId: 'order_Nx1', signature: 'sig'));
      expect(rec.status, PaymentStatus.paid);
      expect(rec.method, 'upi');
      expect(adapter.calls[1].path, '/rides/$rideId/payment/verify');
      expect(adapter.jsonBody(1), {
        'razorpay_payment_id': 'pay_1',
        'razorpay_order_id': 'order_Nx1',
        'razorpay_signature': 'sig',
      });
    });

    test('order errors (real bodies): 503 PAYMENTS_UNAVAILABLE, 409 RIDE_NOT_PAYABLE (not completed / already paid); verify 422', () async {
      for (final (name, code, status) in [
        ('payment_order_unavailable_503.json', 'PAYMENTS_UNAVAILABLE', 503),
        ('payment_order_not_payable_409.json', 'RIDE_NOT_PAYABLE', 409),
        // The API answers RIDE_NOT_PAYABLE (not ALREADY_PAID) for a paid ride.
        ('payment_order_already_paid_409.json', 'RIDE_NOT_PAYABLE', 409),
      ]) {
        final adapter = FakeAdapter((_) => fromFixture(name, status));
        await expectLater(PaymentsApi(client(adapter)).createOrder(rideId), throwsApi(code, status));
      }
      final mismatch = FakeAdapter((_) => fromFixture('payment_verify_order_mismatch.json', 422));
      await expectLater(
        PaymentsApi(client(mismatch)).verify(rideId, const RazorpayResult(paymentId: 'p', orderId: 'o', signature: 's')),
        throwsApi('ORDER_MISMATCH', 422),
      );
    });

    test('FakeRazorpayLauncher records options and resolves manually', () async {
      final launcher = FakeRazorpayLauncher(manual: true);
      final order = PaymentOrder.fromJson({'razorpay_order_id': 'order_1', 'amount': 100, 'currency': 'INR', 'key_id': 'k'});
      final f = launcher.checkout(RazorpayCheckout(order: order, contact: '+911', name: 'Ride', description: 'd'));
      expect(launcher.isOpen, isTrue);
      launcher.complete(FakeRazorpayLauncher.success('order_1'));
      final outcome = await f as RazorpaySuccess;
      expect(outcome.result.orderId, 'order_1');
      expect(outcome.result.paymentId, 'pay_1');
      expect(launcher.opened.single.order.keyId, 'k');
    });
  });

  group('SosFlow', () {
    test('dials 112 first, then posts the alert', () async {
      final adapter = FakeAdapter((_) => fromFixture('sos_rider_201.json', 201));
      final order = <String>[];
      final flow = SosFlow(
        api: RideApi(client(adapter)),
        launch: (uri) async {
          order.add('dial ${uri.toString()}');
          return true;
        },
      );
      final result = await flow.raise(rideId: rideId, at: const GeoPoint(28.62, 77.22));
      expect(result.dialled, isTrue);
      expect(result.alerted, isTrue);
      expect(order, ['dial tel:112']);
      expect(adapter.calls.single.path, '/rides/$rideId/sos');
      expect(adapter.jsonBody(0), {'lat': 28.62, 'lng': 77.22});
    });

    test('no dialer and a failed POST are reported, never thrown', () async {
      final adapter = FakeAdapter((_) => apiError(404, 'NOT_FOUND', 'Ride not found'));
      final flow = SosFlow(api: RideApi(client(adapter)), launch: (_) async => throw Exception('no dialer'));
      final result = await flow.raise(rideId: 'nope', at: const GeoPoint(1, 2));
      expect(result.dialled, isFalse);
      expect(result.alerted, isFalse);
      expect(result.error, isA<ApiException>());
    });
  });
}
