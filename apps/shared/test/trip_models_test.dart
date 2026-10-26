import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

void main() {
  group('Ride through the trip (real API payloads)', () {
    test('ARRIVED driver view reveals the rider phone; rider view reveals the driver phone', () {
      final d = Ride.fromJson(fixture('ride_arrived_driver_view.json'));
      expect(d.status, RideStatus.arrived);
      expect(d.arrivedAt, isNotNull);
      expect(d.rider!.phone, '+919811000778');
      expect(d.rider!.canCall, isTrue);
      expect(d.amountDue, isNull);
      final r = Ride.fromJson(fixture('ride_arrived_rider_view.json'));
      expect(r.driver!.phone, '+919811000777');
      expect(r.driver!.canCall, isTrue);
      expect(r.tripOtp, matches(RegExp(r'^\d{4}$')));
    });

    test('STARTED hides the OTP from the rider', () {
      final r = Ride.fromJson(fixture('ride_started_rider_view.json'));
      expect(r.status, RideStatus.started);
      expect(r.startedAt, isNotNull);
      expect(r.tripOtp, isNull);
      expect(r.shareToken, hasLength(32));
    });

    test('COMPLETED carries the final fare, the carried cancellation fee and amount_due', () {
      final r = Ride.fromJson(fixture('ride_completed_driver_view.json'));
      expect(r.status, RideStatus.completed);
      expect(r.finalFare, 88);
      expect(r.cancellationFee, 30);
      expect(r.amountDue, 118);
      expect(r.dueAmount, 118);
      expect(r.actualDistanceM, 3115);
      expect(r.actualDurationS, 12);
      expect(r.completedAt, isNotNull);
      expect(r.paidAt, isNull);
      expect(r.hasReceipt, isTrue);
      expect(r.isRateable, isTrue);
      // The rider's own view agrees and still has the share token.
      final rv = Ride.fromJson(fixture('ride_completed_rider_view.json'));
      expect(rv.amountDue, 118);
      expect(rv.shareToken, isNotNull);
      expect(rv.driver!.phone, isNotNull);
    });

    test('PAID after cash collected', () {
      final r = Ride.fromJson(fixture('ride_paid_rider_view.json'));
      expect(r.status, RideStatus.paid);
      expect(r.status.isTerminal, isTrue);
      expect(r.paidAt, isNotNull);
      expect(r.amountDue, 118);
      expect(r.lastEventAt, r.paidAt);
    });

    test('rider cancel after ARRIVED carries the ₹30 fee', () {
      final r = Ride.fromJson(fixture('ride_cancelled_after_arrived_fee.json'));
      expect(r.status, RideStatus.cancelled);
      expect(r.cancelledBy, CancelActor.rider);
      expect(r.cancellationFee, 30);
      expect(r.amountDue, isNull);
      expect(r.cancelReason, 'Changed plans');
      expect(r.arrivedAt, isNotNull);
      expect(r.hasReceipt, isFalse);
    });

    test('driver cancel re-queues the ride: REQUESTED with no driver', () {
      final r = Ride.fromJson(fixture('driver_cancel_requeued.json'));
      expect(r.status, RideStatus.requested);
      expect(r.driver, isNull);
      expect(r.acceptedAt, isNull);
      expect(r.cancellationFee, 0);
      expect(r.rider, isNotNull);
      final free = Ride.fromJson(fixture('ride_cancelled_requested_free.json'));
      expect(free.cancellationFee, 0);
      expect(free.cancelledBy, CancelActor.rider);
    });

    test('dueAmount falls back to fare + fee when amount_due is absent', () {
      final json = fixture('ride_completed_driver_view.json')..remove('amount_due');
      expect(Ride.fromJson(json).dueAmount, 118);
      expect(Ride.fromJson(fixture('ride_requested.json')).dueAmount, isNull);
    });
  });

  group('Ride.apply() for later statuses', () {
    final now = DateTime.utc(2026, 10, 4, 7);

    test('ACCEPTED → ARRIVED keeps the OTP and reveals the phone', () {
      final r = Ride.fromJson(fixture('ride_accepted_rider_view.json'));
      final a = r.apply(RideStatusEvent.fromJson(fixture('ws_ride_status_arrived_rider.json')..['ride_id'] = r.id), now: now);
      expect(a.status, RideStatus.arrived);
      expect(a.tripOtp, isNotNull);
      expect(a.driver!.phone, '+919811000777');
      expect(a.arrivedAt, now);
      expect(a.acceptedAt, r.acceptedAt);
    });

    test('ARRIVED → STARTED clears the OTP', () {
      final r = Ride.fromJson(fixture('ride_arrived_rider_view.json'));
      final s = r.apply(RideStatusEvent.fromJson(fixture('ws_ride_status_started_rider.json')..['ride_id'] = r.id), now: now);
      expect(s.status, RideStatus.started);
      expect(s.tripOtp, isNull);
      expect(s.startedAt, now);
    });

    test('STARTED → COMPLETED merges fare, fee and amount_due; → PAID keeps them', () {
      final r = Ride.fromJson(fixture('ride_started_rider_view.json'));
      final ev = RideStatusEvent.fromJson(fixture('ws_ride_status_completed_rider.json')..['ride_id'] = r.id);
      expect(ev.amountDue, 118);
      final c = r.apply(ev, now: now);
      expect(c.status, RideStatus.completed);
      expect(c.finalFare, 88);
      expect(c.cancellationFee, 30);
      expect(c.amountDue, 118);
      expect(c.completedAt, now);
      final p = c.apply(RideStatusEvent.fromJson(fixture('ws_ride_status_paid_rider.json')..['ride_id'] = r.id),
          now: now.add(const Duration(minutes: 1)));
      expect(p.status, RideStatus.paid);
      expect(p.amountDue, 118);
      expect(p.paidAt, now.add(const Duration(minutes: 1)));
      expect(p.completedAt, now);
    });

    test('driver re-queue: REQUESTED on an ACCEPTED ride drops driver, OTP and accepted_at', () {
      final r = Ride.fromJson(fixture('ride_accepted_rider_view.json'));
      final q = r.apply(RideStatusEvent.fromJson(fixture('ws_ride_status_requeued_rider.json')..['ride_id'] = r.id));
      expect(q.status, RideStatus.requested);
      expect(q.isSearching, isTrue);
      expect(q.driver, isNull);
      expect(q.tripOtp, isNull);
      expect(q.acceptedAt, isNull);
      expect(q.requestedAt, r.requestedAt);
    });

    test('driver loses the ride after its own cancel: reassigned flag', () {
      final e = RideStatusEvent.fromJson(fixture('ws_ride_status_driver_after_own_cancel.json'));
      expect(e.status, RideStatus.cancelled);
      expect(e.reassigned, isTrue);
      final fee = RideStatusEvent.fromJson(fixture('ws_ride_status_cancelled_fee_rider.json'));
      expect(fee.cancellationFee, 30);
      expect(fee.cancelledBy, CancelActor.rider);
    });
  });

  test('RidePageResult parses history pages and knows about more pages', () {
    final p1 = RidePageResult.fromJson(fixture('driver_rides_page_small.json'));
    expect(p1.page, 1);
    expect(p1.limit, 2);
    expect(p1.total, 3);
    expect(p1.data, hasLength(2));
    expect(p1.hasMore, isTrue);
    expect(p1.data.first.status, RideStatus.paid);
    expect(p1.data.first.amountDue, 118);
    final p2 = RidePageResult.fromJson(fixture('rides_page_small.json'));
    expect(p2.page, 2);
    expect(p2.total, 6);
    expect(p2.hasMore, isTrue);
    final all = RidePageResult.fromJson(fixture('rides_page1.json'));
    expect(all.data, hasLength(6));
    expect(all.hasMore, isFalse);
    expect(all.data.map((r) => r.status.wire), contains('NO_DRIVER'));
  });

  group('receipt', () {
    test('COMPLETED cash receipt with a carried cancellation fee', () {
      final r = RideReceipt.fromJson(fixture('receipt_completed_cash.json'));
      expect(r.status, RideStatus.completed);
      expect(r.currency, 'INR');
      expect(r.distanceM, 3115);
      expect(r.durationS, 12);
      expect(r.components.baseFare, 50);
      expect(r.components.distance, 37.38);
      expect(r.components.time, 0.3);
      expect(r.components.nightMultiplier, isNull);
      expect(r.components.raw, 87.68);
      expect(r.components.minFareApplied, isFalse);
      expect(r.components.capApplied, isFalse);
      expect(r.components.cap, 123.65);
      expect(r.fare, 88);
      expect(r.gst, 4.19);
      expect(r.fareExclGst, 83.81);
      expect(r.cancellationFee, 30);
      expect(r.hasCancellationFee, isTrue);
      expect(r.total, 118);
      expect(r.paymentMethod, PaymentMethod.cash);
      expect(r.paymentStatus, PaymentStatus.pending);
      expect(r.isPaid, isFalse);
      expect(r.paidWith, isNull);
      expect(r.gstPct, 5);
    });

    test('PAID receipt records how it was paid', () {
      final r = RideReceipt.fromJson(fixture('receipt_paid_cash.json'));
      expect(r.status, RideStatus.paid);
      expect(r.isPaid, isTrue);
      expect(r.paidWith, 'cash');
      expect(r.paidAt, isNotNull);
    });
  });

  test('earnings today / week', () {
    final t = DriverEarnings.fromJson(fixture('driver_earnings_today.json'));
    expect(t.period, EarningsPeriod.today);
    expect(t.from, isNotNull);
    expect(t.rides, 1);
    expect(t.gross, 88);
    expect(t.commission, 12.57);
    expect(t.gst, 4.19);
    expect(t.net, 71.24);
    expect(t.cashCollected, 118);
    expect(t.online, 0);
    final w = DriverEarnings.fromJson(fixture('driver_earnings_week.json'));
    expect(w.period, EarningsPeriod.week);
    expect(w.from!.isBefore(t.from!), isTrue);
    const e = DriverEarnings.empty(EarningsPeriod.week);
    expect(e.rides, 0);
    expect(e.net, 0);
  });

  test('payment models', () {
    final order = PaymentOrder.fromJson({
      'razorpay_order_id': 'order_Nx1',
      'amount': 11800,
      'currency': 'INR',
      'key_id': 'rzp_test_abc',
    });
    expect(order.amountRupees, 118);
    const result = RazorpayResult(paymentId: 'pay_1', orderId: 'order_Nx1', signature: 's');
    expect(result.toJson(), {
      'razorpay_payment_id': 'pay_1',
      'razorpay_order_id': 'order_Nx1',
      'razorpay_signature': 's',
    });
    final checkout = RazorpayCheckout(
        order: order, contact: '+919811000778', name: 'Ride', description: 'Trip to India Gate');
    final opts = checkout.toOptions();
    expect(opts['key'], 'rzp_test_abc');
    expect(opts['order_id'], 'order_Nx1');
    expect(opts['amount'], 11800);
    expect((opts['prefill'] as Map)['contact'], '+919811000778');
    expect((opts['prefill'] as Map).containsKey('email'), isFalse);

    final paid = PaymentStatusEvent.fromJson(fixture('ws_payment_status_paid_driver.json'));
    expect(paid.isPaid, isTrue);
    expect(paid.isCash, isTrue);
    final failed = PaymentStatusEvent.fromJson({'ride_id': 'r', 'status': 'failed', 'method': 'upi'});
    expect(failed.isPaid, isFalse);
    expect(failed.status, PaymentStatus.failed);

    final record = PaymentRecord.fromJson({
      'id': 'p1',
      'ride_id': 'r1',
      'method': 'upi',
      'amount': '118.00',
      'status': 'paid',
      'gateway_order_id': 'order_Nx1',
      'gateway_payment_id': 'pay_1',
      'paid_at': '2026-10-04T06:39:01.794Z',
      'created_at': '2026-10-04T06:38:01.794Z',
    });
    expect(record.amount, 118);
    expect(record.status, PaymentStatus.paid);
    expect(record.paidAt, isNotNull);

    final rating = RatingResult.fromJson(fixture('rating_rider_201.json'));
    expect(rating.stars, 5);
    expect(rating.comment, 'Smooth ride');
    expect(RatingResult.fromJson(fixture('rating_driver_201.json')).comment, isNull);
  });

  test('formatting and share URL helpers', () {
    expect(formatAmount(118), '₹118');
    expect(formatAmount(4.19), '₹4.19');
    expect(formatAmount(12.5), '₹12.50');
    expect(formatAmount(-12.57), '-₹12.57');
    expect(formatAmount(87.999), '₹88');
    expect(formatClock(12), '0:12');
    expect(formatClock(725), '12:05');
    expect(formatClock(3723), '1:02:03');
    const cfg = AppConfig(apiBaseUrl: 'http://10.0.2.2:3000');
    expect(cfg.shareUrl('abc123'), 'http://10.0.2.2:3000/v1/share/abc123');
  });
}
