import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:ride_shared/testing.dart';

import 'helpers.dart';

typedef Harness = ({
  FakeRideApi api,
  FakePaymentsApi payments,
  FakeRazorpayLauncher razorpay,
  RecordingShareSheet share,
  DialerHarness dialer,
  SocketHarness sockets,
});

/// Launches with [ride] active. Uses [settle] because the payment screens
/// show an indeterminate spinner while waiting.
Future<Harness> launch(WidgetTester tester, Ride ride,
    {RazorpayOutcome? razorpayOutcome, RideReceipt? receipt}) async {
  tallScreen(tester);
  final h = (
    api: FakeRideApi()
      ..activeRide = ride
      ..receiptResult = receipt,
    payments: FakePaymentsApi(),
    razorpay: FakeRazorpayLauncher(outcome: razorpayOutcome ?? const RazorpayFailure(RazorpayFailureKind.cancelled)),
    share: RecordingShareSheet(),
    dialer: DialerHarness(),
    sockets: SocketHarness(),
  );
  await tester.pumpWidget(testApp(
    auth: FakeAuthApi(),
    me: FakeMeApi(rider(name: 'Asha')),
    tokens: saved,
    rides: h.api,
    payments: h.payments,
    razorpay: h.razorpay,
    share: h.share,
    dialer: h.dialer,
    sockets: h.sockets,
  ));
  await settle(tester);
  h.sockets.connect();
  await settle(tester);
  return h;
}

Ride completedRide({String payment = 'cash'}) =>
    rideFrom('ride_completed_rider_view.json', (j) => j['payment_method'] = payment);

RideReceipt receipt({String payment = 'cash'}) =>
    RideReceipt.fromJson(fixture('receipt_completed_cash.json')..['payment_method'] = payment);

void main() {
  group('Trip in progress', () {
    testWidgets('STARTED: drop marker, track and guide lines, live car, Share + SOS, no cancel', (tester) async {
      final ride = rideFrom('ride_started_rider_view.json');
      final h = await launch(tester, ride);

      expect(find.text('Trip in progress'), findsOneWidget);
      expect(find.text('Heading to India Gate, New Delhi'), findsOneWidget);
      expect(find.text('₹94 – ₹109'), findsOneWidget); // fare pill
      expect(find.textContaining('pickup,drop lines:track,route'), findsOneWidget);
      expect(find.byKey(const Key('cancel-ride')), findsNothing);
      expect(find.text('DL01CP2002'), findsOneWidget);

      h.sockets.emit('driver:position', fixture('ws_driver_position.json')..['ride_id'] = ride.id);
      await tester.pumpAndSettle();
      expect(find.textContaining('pickup,drop,car lines:track,route'), findsOneWidget);

      // Share trip → the public share URL for the ride's token.
      await tester.tap(find.byKey(const Key('share')));
      await tester.pumpAndSettle();
      expect(h.share.shared.single.text, 'Track my ride live: http://api.test/v1/share/${ride.shareToken}');

      // SOS: confirm → dial 112 → POST sos with the rider's position → toast.
      await tester.tap(find.byKey(const Key('sos')));
      await tester.pumpAndSettle();
      expect(find.text('Emergency SOS'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sos-confirm')));
      await tester.pumpAndSettle();
      expect(h.dialer.dialled.single.toString(), 'tel:112');
      expect(h.api.sosCalls.single, (id: ride.id, lat: 28.6315, lng: 77.2167));
      expect(find.text('Our team has been alerted'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SOS cancel in the dialog does nothing; a failed POST says so', (tester) async {
      final ride = rideFrom('ride_arrived_rider_view.json');
      final h = await launch(tester, ride);
      await tester.tap(find.byKey(const Key('sos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.dialer.dialled, isEmpty);
      expect(h.api.sosCalls, isEmpty);

      h.api.sosError = const ApiException(code: 'NETWORK_ERROR', message: 'offline');
      await tester.tap(find.byKey(const Key('sos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sos-confirm')));
      await tester.pumpAndSettle();
      expect(h.dialer.dialled.single.toString(), 'tel:112');
      expect(find.textContaining("couldn't alert our team"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Fare & payment', () {
    testWidgets('cash: receipt breakdown, pay-cash instruction, payment:status paid → Rate → Home',
        (tester) async {
      final ride = completedRide();
      final h = await launch(tester, ride, receipt: receipt());
      final api = h.api;
      final sockets = h.sockets;
      expect(api.receiptCalls, 1);

      expect(find.text('Trip completed'), findsOneWidget);
      expect(find.byKey(const Key('pay-cash')), findsOneWidget);
      expect(find.text('Pay ₹118 cash to your driver'), findsOneWidget);
      expect(find.text('Trip fare'), findsOneWidget);
      expect(find.text('₹88'), findsOneWidget);
      expect(find.text('Includes ₹4.19 GST'), findsOneWidget);
      expect(find.text('Cancellation fee (earlier ride)'), findsOneWidget);
      expect(find.text('₹30'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹118'), findsOneWidget);
      expect(find.text('3.1 km · 0:12'), findsOneWidget);
      expect(find.text('Waiting for your driver to confirm…'), findsOneWidget);
      expect(find.byKey(const Key('pay-online')), findsNothing);

      sockets.emit('payment:status', fixture('ws_payment_status_paid_rider.json')..['ride_id'] = ride.id);
      await tester.pumpAndSettle();

      expect(find.text('Payment received'), findsOneWidget);
      expect(find.text('How was your trip?'), findsOneWidget);
      expect(find.text('Rate your ride with Phase Two Driver'), findsOneWidget);
      final submit = tester.widget<PrimaryButton>(find.byKey(const Key('rate-submit')));
      expect(submit.onPressed, isNull); // no stars yet

      await tester.tap(find.byKey(const Key('star-5')));

      await tester.pump();
      await tester.enterText(find.byKey(const Key('rate-comment')), 'Smooth ride');
      await tester.tap(find.byKey(const Key('rate-submit')));
      await tester.pumpAndSettle();

      expect(api.rated.single, (id: ride.id, stars: 5, comment: 'Smooth ride'));
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.text('Thanks for your feedback'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('online: Pay → order → Razorpay Checkout → verify → PAID → Rate; Skip → Home', (tester) async {
      final ride = completedRide(payment: 'online');
      final h = await launch(tester, ride, razorpayOutcome: FakeRazorpayLauncher.success('order_test1'));

      expect(find.byKey(const Key('pay-cash')), findsNothing);
      expect(find.text('Pay ₹118 online'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pay-online')));
      await tester.pumpAndSettle();

      expect(h.payments.orders.single, ride.id);
      final opened = h.razorpay.opened.single;
      expect(opened.order.razorpayOrderId, 'order_test1');
      expect(opened.order.keyId, 'rzp_test_key');
      expect(opened.contact, '+919800000002');
      expect(opened.toOptions()['amount'], 11800);
      expect(h.payments.verified.single.rideId, ride.id);
      expect(h.payments.verified.single.result.paymentId, 'pay_test1');
      expect(h.payments.verified.single.result.orderId, 'order_test1');

      expect(find.text('How was your trip?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rate-skip')));
      await tester.pumpAndSettle();
      expect(h.api.rated, isEmpty);
      expect(find.text('Where to?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('online failure: message, Retry, or switch to cash', (tester) async {
      final ride = completedRide(payment: 'online');
      final h = await launch(tester, ride);
      h.api.receiptResult = receipt(payment: 'online');

      await tester.tap(find.byKey(const Key('pay-online')));
      await tester.pumpAndSettle();
      expect(find.text('You cancelled the payment.'), findsOneWidget);
      expect(find.byKey(const Key('pay-retry')), findsOneWidget);
      expect(find.text('Pay cash to the driver instead'), findsOneWidget);
      expect(h.payments.verified, isEmpty);

      h.razorpay.outcome = const RazorpayFailure(RazorpayFailureKind.network, message: 'Network error');
      await tester.tap(find.byKey(const Key('pay-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Network error'), findsOneWidget);
      expect(h.payments.orders, hasLength(2));

      await tester.tap(find.byKey(const Key('pay-switch-cash')));
      await settle(tester);
      expect(find.text('Pay ₹118 cash to your driver'), findsOneWidget);
      expect(find.textContaining('your driver can confirm cash after a few minutes'), findsOneWidget);

      // The driver confirms cash: ride:status PAID closes the screen too.
      h.sockets.emit('ride:status', fixture('ws_ride_status_paid_rider.json')..['ride_id'] = ride.id);
      await tester.pumpAndSettle();
      expect(find.text('How was your trip?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('verify failure keeps Retry; 503 PAYMENTS_UNAVAILABLE offers cash only', (tester) async {
      final ride = completedRide(payment: 'online');
      final h = await launch(tester, ride, razorpayOutcome: FakeRazorpayLauncher.success('order_test1'));
      h.payments.verifyError = const ApiException(code: 'SIGNATURE_INVALID', message: 'bad', statusCode: 400);

      await tester.tap(find.byKey(const Key('pay-online')));
      await tester.pumpAndSettle();
      expect(find.textContaining("couldn't confirm the payment yet"), findsOneWidget);
      expect(find.byKey(const Key('pay-retry')), findsOneWidget);
      expect(find.text('Trip completed'), findsOneWidget);

      h.payments.orderError =
          const ApiException(code: 'PAYMENTS_UNAVAILABLE', message: 'Online payments are not configured', statusCode: 503);
      await tester.tap(find.byKey(const Key('pay-retry')));
      await tester.pumpAndSettle();
      expect(find.text("Online payment isn't available right now. Please pay cash."), findsOneWidget);
      expect(find.byKey(const Key('pay-retry')), findsNothing);
      expect(find.byKey(const Key('pay-switch-cash')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('resume after the ride was paid elsewhere: active 404 → GET ride → Rate screen', (tester) async {
      final ride = completedRide();
      final h = await launch(tester, ride);
      final paid = rideFrom('ride_paid_rider_view.json', (j) => j['id'] = ride.id);
      h.api.activeRide = null;
      h.api.historyRides = [paid];

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(h.api.fetched, contains(ride.id));
      expect(find.text('How was your trip?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
