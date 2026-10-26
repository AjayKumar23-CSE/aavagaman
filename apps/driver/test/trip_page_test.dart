import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'helpers.dart';

typedef Trip = ({FakeRideApi rides, SocketHarness sockets, List<Uri> dialled});

/// Frames without waiting to settle: the online-payment spinner never stops.
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<Trip> launchWith(WidgetTester tester, Ride active, {bool spinner = false}) async {
  Future<void> settle() => spinner ? frames(tester) : tester.pumpAndSettle();
  tallScreen(tester);
  final rides = FakeRideApi()..activeRide = active;
  final sockets = SocketHarness();
  final dialled = <Uri>[];
  await tester.pumpWidget(testApp(
    driver: FakeDriverApi(approvedProfile()),
    rides: rides,
    sockets: sockets,
    overrides: [
      sosFlowProvider.overrideWithValue(SosFlow(api: rides, launch: (uri) async {
        dialled.add(uri);
        return true;
      })),
    ],
  ));
  await settle();
  sockets.connect();
  await settle();
  return (rides: rides, sockets: sockets, dialled: dialled);
}

Future<void> enterOtp(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('otp-field')), code);
  await tester.pumpAndSettle();
}

Future<void> confirmDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cash trip: Arrived → wrong OTP → Start → End → Cash collected → Rate → Home', (tester) async {
    final t = await launchWith(tester, rideFrom('ride_accepted_driver_view.json'));
    final id = t.rides.activeRide!.id;
    expect(find.text('Head to the pickup'), findsOneWidget);

    await tester.tap(find.byKey(const Key('arrived')));
    await tester.pumpAndSettle();
    expect(t.rides.arrivedCalls.single, (id: id, lat: cpFix.lat, lng: cpFix.lng));
    expect(find.text("You're at the pickup — waiting for the rider"), findsOneWidget);
    // Full phone once ARRIVED; calling unlocks.
    expect(tester.widget<IconButton>(find.byKey(const Key('call-rider'))).onPressed, isNotNull);

    t.rides.startError =
        const ApiException(code: 'OTP_INVALID', message: 'Wrong OTP. 2 attempts left.', statusCode: 401);
    await enterOtp(tester, '1111');
    expect(find.text('Wrong OTP. 2 attempts left.'), findsOneWidget);
    expect(find.text("You're at the pickup — waiting for the rider"), findsOneWidget);

    t.rides.startError = null;
    await enterOtp(tester, '4821');
    expect(t.rides.startCalls.last.otp, '4821');
    expect(find.text('Trip in progress'), findsOneWidget);
    expect(find.text('Navigate to drop'), findsOneWidget);
    expect(find.byKey(const Key('cancel-ride')), findsNothing); // no cancel once STARTED

    await tester.tap(find.byKey(const Key('end')));
    await tester.pumpAndSettle();
    expect(find.text('End the trip?'), findsOneWidget);
    await confirmDialog(tester);
    expect(t.rides.completeCalls, hasLength(1));
    expect(find.text('Collect payment'), findsOneWidget);
    expect(find.byKey(const Key('amount-due')), findsOneWidget);
    expect(find.text('₹118'), findsOneWidget); // fare 88 + earlier cancellation fee 30
    expect(find.text('₹88'), findsOneWidget);
    expect(find.text('₹30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cash-collected')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm you received ₹118 in cash from the rider.'), findsOneWidget);
    await confirmDialog(tester);
    expect(t.rides.cashCalls, [id]);
    expect(find.byKey(const Key('payment-received')), findsOneWidget);

    expect(tester.widget<FilledButton>(find.descendant(
            of: find.byKey(const Key('rate-submit')), matching: find.byType(FilledButton)))
        .onPressed, isNull);
    await tester.tap(find.byKey(const Key('star-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rate-submit')));
    await tester.pumpAndSettle();
    expect(t.rides.rated.single, (id: id, stars: 4));
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    expect(t.rides.earningsCalls, contains(EarningsPeriod.today));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('masked calling: Call bridges through the app from ACCEPTED and the rider number stays private',
      (tester) async {
    final t = await launchWith(
      tester,
      rideFrom('ride_accepted_driver_view.json', (j) => (j['rider'] as Map)['call_via'] = '+911140001234'),
    );
    expect(find.textContaining('Number private · calls go via Aavagaman'), findsOneWidget);
    expect(find.textContaining('+91'), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const Key('call-rider'))).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('call-rider')));
    await tester.pumpAndSettle();
    expect(t.rides.callRequests, [t.rides.activeRide!.id]);
    expect(t.dialled, isEmpty);
    expect(find.textContaining('Pick up to talk to the rider'), findsOneWidget);
  });

  testWidgets('trip screen shows a map with the pickup and drop until the trip ends', (tester) async {
    await launchWith(tester, rideFrom('ride_accepted_driver_view.json'));
    expect(find.byKey(const Key('trip-map')), findsOneWidget);
    expect(find.textContaining('pickup,drop'), findsOneWidget);
    expect(find.byKey(const Key('navigate')), findsOneWidget);
  });

  testWidgets('Arrived too far from the pickup keeps the server message', (tester) async {
    final t = await launchWith(tester, rideFrom('ride_accepted_driver_view.json'));
    t.rides.arrivedError = const ApiException(
        code: 'TOO_FAR_FROM_PICKUP', message: 'You are 812 m from the pickup; get within 300 m', statusCode: 422);
    await tester.tap(find.byKey(const Key('arrived')));
    await tester.pumpAndSettle();
    expect(find.text('You are 812 m from the pickup; get within 300 m'), findsOneWidget);
    expect(find.text('Head to the pickup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('online payment: waits for payment:status, then the rating can be skipped', (tester) async {
    final t = await launchWith(
      tester,
      rideFrom('ride_completed_driver_view.json', (j) => j['payment_method'] = 'online'),
      spinner: true,
    );
    expect(find.byKey(const Key('waiting-online')), findsOneWidget);

    t.sockets.emit('payment:status', {'ride_id': t.rides.activeRide!.id, 'status': 'paid', 'method': 'online'});
    await frames(tester);
    expect(find.byKey(const Key('payment-received')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rate-skip')));
    await tester.pumpAndSettle();
    expect(t.rides.rated, isEmpty);
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cash collected refused while an online payment is pending', (tester) async {
    final t = await launchWith(
      tester,
      rideFrom('ride_completed_driver_view.json', (j) => j['payment_method'] = 'online'),
      spinner: true,
    );
    t.rides.cashError = const ApiException(
        code: 'PAYMENT_PENDING', message: 'The rider is paying online. Wait a few minutes.', statusCode: 409);
    await tester.tap(find.byKey(const Key('cash-collected')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('confirm')));
    await frames(tester);
    expect(find.text('The rider is paying online. Wait a few minutes.'), findsOneWidget);
    expect(find.byKey(const Key('waiting-online')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel: reason picker, no-show locked before 5 min, re-queued ride explained', (tester) async {
    final t = await launchWith(tester, rideFrom('ride_arrived_driver_view.json', (j) {
      j['arrived_at'] = DateTime.now().toUtc().toIso8601String();
    }));
    final id = t.rides.activeRide!.id;

    await tester.tap(find.byKey(const Key('cancel-ride')));
    await tester.pumpAndSettle();
    expect(find.text('Available after waiting 5 min at the pickup'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const Key('reason-riderNoShow'))).enabled, isFalse);
    expect(tester.widget<FilledButton>(find.byKey(const Key('cancel-confirm'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('reason-other')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('cancel-confirm'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('reason-note')), 'Puncture');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-confirm')));
    await tester.pumpAndSettle();

    expect(t.rides.cancelCalls.single, (id: id, reason: 'Other: Puncture'));
    expect(find.text('You cancelled this ride. It has gone back to other drivers.'), findsOneWidget);
    // The re-queue event that follows must not relabel it as a reassignment.
    t.sockets.emit('ride:status', {'ride_id': id, 'status': 'REQUESTED', 'reassigned': true});
    await tester.pumpAndSettle();
    expect(find.text('You cancelled this ride. It has gone back to other drivers.'), findsOneWidget);

    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no-show after waiting 5 min cancels with a fee to the rider', (tester) async {
    final t = await launchWith(tester, rideFrom('ride_arrived_driver_view.json', (j) {
      j['arrived_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 6)).toIso8601String();
    }));
    t.rides.cancelResult = rideFrom('ride_arrived_driver_view.json', (j) {
      j['id'] = t.rides.activeRide!.id;
      j['status'] = 'CANCELLED';
      j['cancelled_by'] = 'driver';
      j['cancel_reason'] = 'Rider no-show';
    });

    await tester.tap(find.byKey(const Key('cancel-ride')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reason-riderNoShow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-confirm')));
    await tester.pumpAndSettle();

    expect(t.rides.cancelCalls.single.reason, 'Rider no-show');
    expect(find.textContaining('rider no-show'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SOS: confirm → dials 112 → alert posted with the position', (tester) async {
    final t = await launchWith(tester, rideFrom('ride_started_driver_view.json'));

    await tester.tap(find.byKey(const Key('sos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sos-confirm')));
    await tester.pumpAndSettle();

    expect(t.dialled.single.toString(), 'tel:112');
    expect(t.rides.sosCalls.single, (id: t.rides.activeRide!.id, lat: cpFix.lat, lng: cpFix.lng));
    expect(find.text('Our support team has been alerted.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
