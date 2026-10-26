import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'helpers.dart';

Ride requestedRide({Duration age = const Duration(seconds: 10)}) => rideFrom('ride_requested.json', (j) {
      j['requested_at'] = DateTime.now().toUtc().subtract(age).toIso8601String();
    });

Future<({FakeRideApi api, SocketHarness sockets})> launchWithRide(WidgetTester tester, Ride? ride) async {
  tallScreen(tester);
  final api = FakeRideApi()..activeRide = ride;
  final sockets = SocketHarness();
  await tester.pumpWidget(testApp(
    auth: FakeAuthApi(),
    me: FakeMeApi(rider(name: 'Asha')),
    tokens: saved,
    rides: api,
    sockets: sockets,
  ));
  await tester.pumpAndSettle();
  sockets.connect();
  await tester.pumpAndSettle();
  return (api: api, sockets: sockets);
}

void main() {
  group('Finding', () {
    testWidgets('launch with a REQUESTED ride → Finding with a 2-minute countdown and re-subscribe',
        (tester) async {
      final h = await launchWithRide(tester, requestedRide());

      expect(h.api.activeCalls, 1);
      expect(find.text('Finding your driver'), findsOneWidget);
      final clock = tester.widget<Text>(find.byKey(const Key('finding-countdown'))).data!;
      expect(clock, matches(RegExp(r'^1:(4|5)\d$')));
      expect(find.text('India Gate, New Delhi'), findsOneWidget);
      expect(h.sockets.socket!.emitted.map((e) => e.event), contains('rider:subscribe'));

      await tester.pump(const Duration(seconds: 30));
      final later = tester.widget<Text>(find.byKey(const Key('finding-countdown'))).data!;
      expect(later, matches(RegExp(r'^1:(1|2)\d$')));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Cancel → confirm → POST cancel → back on Home', (tester) async {
      final h = await launchWithRide(tester, requestedRide());

      await tester.tap(find.byKey(const Key('cancel-ride')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this ride?'), findsOneWidget);
      await tester.tap(find.text('Keep looking'));
      await tester.pumpAndSettle();
      expect(h.api.cancelled, isEmpty);

      await tester.tap(find.byKey(const Key('cancel-ride')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();

      expect(h.api.cancelled.single, h.api.fetched.isEmpty ? isNotEmpty : isNotEmpty);
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.text('Your ride was cancelled'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ride:no_driver shows the message and Back to home dismisses', (tester) async {
      final h = await launchWithRide(tester, requestedRide());
      final id = h.api.activeRide!.id;

      h.sockets.emit('ride:no_driver', {'ride_id': id});
      h.sockets.emit('ride:status', {'ride_id': id, 'status': 'NO_DRIVER'});
      h.api.activeRide = null; // the server no longer has an active ride
      await tester.pumpAndSettle();

      expect(find.text('No drivers available'), findsOneWidget);
      expect(find.textContaining('try again in a few minutes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismiss-ride')));
      await tester.pumpAndSettle();
      expect(find.text('Where to?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Assigned', () {
    testWidgets('ride:status ACCEPTED → driver card, plate, big OTP, Call locked, Share/SOS live',
        (tester) async {
      final h = await launchWithRide(tester, requestedRide());
      final accepted = fixture('ws_ride_status_accepted_rider.json')..['ride_id'] = h.api.activeRide!.id;
      // The quiet re-fetch after the event returns the ACCEPTED ride.
      h.api.activeRide = rideFrom('ride_accepted_rider_view.json', (j) {
        j['id'] = h.api.activeRide!.id;
        j['accepted_at'] = DateTime.now().toUtc().toIso8601String();
      });

      h.sockets.emit('ride:status', accepted);
      await tester.pumpAndSettle();

      expect(find.text('Your driver is on the way'), findsOneWidget);
      expect(find.text('Phase Two Driver'), findsOneWidget);
      expect(find.text('DL01CP2002'), findsOneWidget);
      expect(find.textContaining('White Maruti Suzuki Dzire'), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget); // rating next to the star icon
      final otp = tester.widget<Text>(find.byKey(const Key('trip-otp'))).data!;
      expect(otp.replaceAll(' ', ''), h.api.activeRide!.tripOtp);
      expect(find.text('Calculating arrival time…'), findsOneWidget);

      IconButton action(String key) => tester.widget<IconButton>(
          find.descendant(of: find.byKey(Key(key)), matching: find.byType(IconButton)));
      expect(action('call').onPressed, isNull);
      expect(action('share').onPressed, isNotNull);
      expect(action('sos').onPressed, isNotNull);
      expect(find.byKey(const Key('cancel-ride')), findsOneWidget);

      // Live position → ETA and a car marker on the map.
      h.sockets.emit('driver:position', fixture('ws_driver_position.json')..['ride_id'] = h.api.activeRide!.id);
      await tester.pumpAndSettle();
      expect(find.text('Arriving in 1 min'), findsOneWidget);
      expect(find.textContaining('pickup,car'), findsOneWidget);

      // ARRIVED reveals the phone → Call enabled.
      h.sockets.emit('ride:status', {
        ...accepted,
        'status': 'ARRIVED',
        'driver': {...(accepted['driver'] as Map), 'phone': '+919811000777'},
      });
      await tester.pumpAndSettle();
      expect(find.text('Your driver has arrived'), findsOneWidget);
      expect(action('call').onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('masked calling: Call is live from ACCEPTED, bridges through the app and never shows a number',
        (tester) async {
      final h = await launchWithRide(tester, requestedRide());
      final accepted = fixture('ws_ride_status_accepted_rider.json')..['ride_id'] = h.api.activeRide!.id;
      (accepted['driver'] as Map)['call_via'] = '+911140001234';
      h.api.activeRide = rideFrom('ride_accepted_rider_view.json', (j) {
        j['id'] = h.api.activeRide!.id;
        j['accepted_at'] = DateTime.now().toUtc().toIso8601String();
        (j['driver'] as Map)['call_via'] = '+911140001234';
      });
      h.sockets.emit('ride:status', accepted);
      await tester.pumpAndSettle();

      IconButton action(String key) => tester.widget<IconButton>(
          find.descendant(of: find.byKey(Key(key)), matching: find.byType(IconButton)));
      expect(action('call').onPressed, isNotNull);
      expect(find.textContaining('+91'), findsNothing);

      await tester.tap(find.byKey(const Key('call')));
      await tester.pumpAndSettle();
      expect(h.api.callRequests, [h.api.activeRide!.id]);
      expect(find.textContaining('Pick up to talk to your driver'), findsOneWidget);

      // Throttled by the server → the message is shown as is (after the first snack bar is gone).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      h.api.callError = const ApiException(code: 'CALL_TOO_SOON', message: 'Please wait a moment before calling again', statusCode: 429);
      await tester.tap(find.byKey(const Key('call')));
      await tester.pumpAndSettle();
      expect(find.text('Please wait a moment before calling again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cancel after accept: fee warning after 2 min; 409 shows the server message',
        (tester) async {
      final ride = rideFrom('ride_accepted_rider_view.json', (j) {
        j['accepted_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String();
      });
      final h = await launchWithRide(tester, ride);
      h.api.cancelError = const ApiException(
          code: 'RIDE_NOT_CANCELLABLE', message: 'This ride can no longer be cancelled here', statusCode: 409);

      await tester.tap(find.byKey(const Key('cancel-ride')));
      await tester.pumpAndSettle();
      expect(find.textContaining('cancellation fee may apply'), findsOneWidget);
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();

      expect(h.api.cancelled.single, ride.id);
      expect(find.text('This ride can no longer be cancelled here'), findsOneWidget);
      expect(find.text('Your driver is on the way'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no fee warning within 2 minutes of accept', (tester) async {
      final ride = rideFrom('ride_accepted_rider_view.json', (j) {
        j['accepted_at'] = DateTime.now().toUtc().toIso8601String();
      });
      await launchWithRide(tester, ride);
      await tester.tap(find.byKey(const Key('cancel-ride')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this ride?'), findsOneWidget);
      expect(find.textContaining('cancellation fee'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('late cancel from ARRIVED shows the actual fee from the response', (tester) async {
    final ride = rideFrom('ride_arrived_rider_view.json', (j) {
      j['accepted_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String();
    });
    final h = await launchWithRide(tester, ride);
    h.api.cancelFee = 30;

    await tester.tap(find.byKey(const Key('cancel-ride')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cancellation fee may apply'), findsOneWidget);
    await tester.tap(find.text('Yes, cancel'));
    await tester.pumpAndSettle();

    expect(h.api.cancelled.single, ride.id);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Your ride was cancelled. A ₹30 cancellation fee will be added to your next trip.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
