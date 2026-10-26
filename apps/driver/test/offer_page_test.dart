import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const rideA = '50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b'; // ws_ride_offer.json
const rideB = 'b2f7c9d0-0000-4000-8000-00000000000b';

String expiresIn(int seconds) => DateTime.now().toUtc().add(Duration(seconds: seconds)).toIso8601String();

Map<String, dynamic> offerJson({int seconds = 20}) => fixture('ws_ride_offer.json')..['expires_at'] = expiresIn(seconds);

/// A second request from another rider, farther away and pricier.
Map<String, dynamic> offerBJson({int seconds = 20}) => {
      'ride_id': rideB,
      'pickup': {'lat': 28.6, 'lng': 77.227, 'address': 'Khan Market, New Delhi'},
      'drop_address': 'Select Citywalk, Saket',
      'distance_to_pickup_m': 2300,
      'est_fare_min': 162,
      'est_fare_max': 187,
      'expires_at': expiresIn(seconds),
    };

Future<({FakeRideApi rides, RecordingOfferAlert alert, SocketHarness sockets})> launchOnline(
    WidgetTester tester) async {
  tallScreen(tester);
  final h = (rides: FakeRideApi(), alert: RecordingOfferAlert(), sockets: SocketHarness());
  await tester.pumpWidget(testApp(
    driver: FakeDriverApi(approvedProfile()),
    rides: h.rides,
    alert: h.alert,
    sockets: h.sockets,
  ));
  await tester.pumpAndSettle();
  h.sockets.connect();
  await tester.pumpAndSettle();
  return h;
}

int countdown(WidgetTester tester) =>
    int.parse(tester.widget<Text>(find.byKey(const Key('offer-countdown-$rideA'))).data!);

void main() {
  testWidgets('ride:offer opens the full-screen popup with details, tone and a countdown', (tester) async {
    final h = await launchOnline(tester);

    h.sockets.emit('ride:offer', offerJson());
    await tester.pumpAndSettle();

    expect(find.text('New ride request'), findsOneWidget);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.text('India Gate, New Delhi'), findsOneWidget);
    expect(find.text('148 m to pickup'), findsOneWidget);
    expect(find.text('Fare ₹94 – ₹109'), findsOneWidget);
    expect(h.alert.ringing, isTrue);
    final start = countdown(tester);
    expect(start, inInclusiveRange(18, 20));

    await tester.pump(const Duration(seconds: 5));
    expect(countdown(tester), start - 5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Accept over the socket → tone stops → Navigate to pickup with the rider card', (tester) async {
    final h = await launchOnline(tester);
    final offer = offerJson();
    h.sockets.socket!.ackHandler = (event, data) =>
        event == 'driver:offer:accept' ? fixture('ws_ack_accept.json') : {'ok': true};

    h.sockets.emit('ride:offer', offer);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-accept-$rideA')));
    await tester.pumpAndSettle();

    expect(h.sockets.socket!.emitted.last.event, 'driver:offer:accept');
    expect(h.sockets.socket!.emitted.last.data, {'ride_id': offer['ride_id']});
    expect(h.rides.accepted, isEmpty); // no REST fallback needed
    expect(h.alert.ringing, isFalse);
    expect(find.text('Navigate to pickup'), findsOneWidget);
    expect(find.text('Head to the pickup'), findsOneWidget);
    expect(find.text('Phase Two Rider'), findsOneWidget);
    expect(find.textContaining('******0778'), findsOneWidget);
    expect(find.byKey(const Key('navigate')), findsOneWidget);
    final call = tester.widget<IconButton>(find.byKey(const Key('call-rider')));
    expect(call.onPressed, isNull); // phone hidden until ARRIVED
    expect(find.text('Arrived'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Accept falls back to REST when the socket times out', (tester) async {
    final h = await launchOnline(tester);
    h.sockets.emit('ride:offer', offerJson());
    await tester.pumpAndSettle();
    h.sockets.socket!.autoAck = false; // lost acknowledgement

    await tester.tap(find.byKey(const Key('offer-accept-$rideA')));
    await tester.pump(const Duration(seconds: 9)); // > ackTimeout (8 s)
    await tester.pumpAndSettle();

    expect(h.rides.accepted, hasLength(1));
    expect(find.text('Navigate to pickup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('409 OFFER_NOT_VALID on accept returns Home with the message', (tester) async {
    final h = await launchOnline(tester);
    h.sockets.socket!.ackHandler = (event, data) =>
        event == 'driver:offer:accept' ? fixture('ws_ack_accept_not_valid.json') : {'ok': true};
    h.sockets.emit('ride:offer', offerJson());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offer-accept-$rideA')));
    await tester.pumpAndSettle();

    expect(find.text('This ride is no longer available'), findsOneWidget);
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    expect(h.alert.ringing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reject emits driver:offer:reject, stops the tone and returns Home', (tester) async {
    final h = await launchOnline(tester);
    final offer = offerJson();
    h.sockets.emit('ride:offer', offer);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offer-reject-$rideA')));
    await tester.pumpAndSettle();

    expect(h.sockets.socket!.emitted.last.event, 'driver:offer:reject');
    expect(h.sockets.socket!.emitted.last.data, {'ride_id': offer['ride_id']});
    expect(h.alert.ringing, isFalse);
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ride:offer:expired and local expiry both close the popup', (tester) async {
    final h = await launchOnline(tester);
    final offer = offerJson();
    h.sockets.emit('ride:offer', offer);
    await tester.pumpAndSettle();
    h.sockets.emit('ride:offer:expired', {'ride_id': offer['ride_id']});
    await tester.pumpAndSettle();
    expect(find.text('New ride request'), findsNothing);
    expect(h.alert.ringing, isFalse);

    h.sockets.emit('ride:offer', offerJson(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('New ride request'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('New ride request'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('several requests are listed together; answering one keeps the others and the tone', (tester) async {
    final h = await launchOnline(tester);
    h.sockets.emit('ride:offer', offerJson());
    h.sockets.emit('ride:offer', offerBJson());
    await tester.pumpAndSettle();

    expect(find.text('2 ride requests'), findsOneWidget);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.text('Khan Market, New Delhi'), findsOneWidget);
    expect(find.text('2.3 km to pickup'), findsOneWidget);
    expect(find.text('Fare ₹162 – ₹187'), findsOneWidget);
    expect(find.byKey(const Key('offer-accept-$rideA')), findsOneWidget);
    expect(find.byKey(const Key('offer-accept-$rideB')), findsOneWidget);
    expect(h.alert.ringing, isTrue);

    // The same request re-sent (reconnect) is not duplicated.
    h.sockets.emit('ride:offer', offerJson());
    await tester.pumpAndSettle();
    expect(find.text('2 ride requests'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offer-reject-$rideA')));
    await tester.pumpAndSettle();
    expect(h.sockets.socket!.emitted.last.event, 'driver:offer:reject');
    expect(h.sockets.socket!.emitted.last.data, {'ride_id': rideA});
    expect(find.text('New ride request'), findsOneWidget); // one left
    expect(find.text('Khan Market, New Delhi'), findsOneWidget);
    expect(find.text('Connaught Place, New Delhi'), findsNothing);
    expect(h.alert.ringing, isTrue);

    // Another driver took the remaining one: the list closes and the tone stops.
    h.sockets.emit('ride:offer:expired', {'ride_id': rideB});
    await tester.pumpAndSettle();
    expect(find.text('New ride request'), findsNothing);
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    expect(h.alert.ringing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed accept drops only that request; the other stays with the message', (tester) async {
    final h = await launchOnline(tester);
    h.sockets.socket!.ackHandler = (event, data) =>
        event == 'driver:offer:accept' ? fixture('ws_ack_accept_not_valid.json') : {'ok': true};
    h.sockets.emit('ride:offer', offerJson());
    h.sockets.emit('ride:offer', offerBJson());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offer-accept-$rideA')));
    await tester.pumpAndSettle();

    expect(find.text('This ride is no longer available'), findsOneWidget);
    expect(find.text('New ride request'), findsOneWidget);
    expect(find.byKey(const Key('offer-accept-$rideB')), findsOneWidget);
    expect(h.alert.ringing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ride:status reassigned ends the trip with an explanation', (tester) async {
    tallScreen(tester);
    final rides = FakeRideApi()..activeRide = rideFrom('ride_accepted_driver_view.json');
    final sockets = SocketHarness();
    await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile()), rides: rides, sockets: sockets));
    await tester.pumpAndSettle();
    sockets.connect();
    await tester.pumpAndSettle();
    expect(find.text('Navigate to pickup'), findsOneWidget);

    sockets.emit('ride:status', {'ride_id': rides.activeRide!.id, 'status': 'CANCELLED', 'reassigned': true});
    rides.activeRide = null;
    await tester.pumpAndSettle();

    expect(find.text('This ride was reassigned to another driver.'), findsOneWidget);
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
