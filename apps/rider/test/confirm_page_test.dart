import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/providers.dart';

import 'helpers.dart';

/// Home → (draft already has pickup+drop) → Confirm, via the real router.
Future<FakeRideApi> openConfirm(
  WidgetTester tester, {
  FakeRideApi? rides,
  SocketHarness? sockets,
  String estimate = 'fare_estimate.json',
}) async {
  tallScreen(tester);
  final api = rides ?? FakeRideApi();
  if (api.estimateJson.isEmpty) api.estimateJson = fixture(estimate);
  await tester.pumpWidget(testApp(
    auth: FakeAuthApi(),
    me: FakeMeApi(rider(name: 'Asha')),
    tokens: saved,
    rides: api,
    sockets: sockets,
    draft: const BookingDraft(pickup: cp, drop: indiaGate),
  ));
  await tester.pumpAndSettle();
  // Home → search → confirm would need Places; jump straight to Confirm.
  await tester.tap(find.byKey(const Key('where-to')));
  await tester.pumpAndSettle();
  expect(find.text('Set drop location'), findsOneWidget);
  // Without a Places key the typed address goes to the map picker.
  await tester.enterText(find.byKey(const Key('search-field')), 'India Gate');
  await tester.pump();
  await tester.tap(find.byKey(const Key('set-on-map')));
  await tester.pumpAndSettle();
  expect(find.text('Set drop on map'), findsOneWidget);
  expect(find.widgetWithText(TextField, 'Address or landmark'), findsOneWidget);
  await tester.tap(find.text('Confirm location'));
  await tester.pumpAndSettle();
  expect(find.text('Confirm your ride'), findsOneWidget);
  return api;
}

void main() {
  testWidgets('shows fare range, trip meta, addresses and Cash selected by default', (tester) async {
    final api = await openConfirm(tester);

    expect(api.estimateCalls, 1);
    expect(find.byKey(const Key('fare-range')), findsOneWidget);
    expect(find.text('₹94 – ₹109'), findsOneWidget);
    expect(find.text('3.1 km · about 7 min'), findsOneWidget);
    // Every vehicle class is listed with its own fare; Sedan is selected by default.
    for (final label in ['Bike', 'Auto', 'Mini', 'Sedan']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('₹44 – ₹51'), findsOneWidget);
    expect(find.text('1 seat'), findsOneWidget);
    expect(find.text('up to 3 seats'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('vehicle-sedan')), matching: find.byKey(const Key('fare-range'))), findsOneWidget);
    // "Where to?" sets the pickup to the phone's position.
    expect(find.text('Current location'), findsOneWidget);
    // The drop came from the map picker with the typed address.
    expect(find.text('India Gate'), findsOneWidget);
    expect(find.byKey(const Key('out-of-area')), findsNothing);

    // Pickup/drop and the Book button are pinned; only fares and payment scroll.
    expect(find.descendant(of: find.byType(ListView), matching: find.byType(RoutePoints)), findsNothing);
    expect(find.descendant(of: find.byType(ListView), matching: find.text('Book ride')), findsNothing);
    expect(find.descendant(of: find.byType(ListView), matching: find.byType(SegmentedButton<PaymentMethod>)), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Book ride'), findsOneWidget);

    final seg = tester.widget<SegmentedButton<PaymentMethod>>(find.byType(SegmentedButton<PaymentMethod>));
    expect(seg.selected, {PaymentMethod.cash});
    final book = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Book ride'));
    expect(book.onPressed, isNotNull);
  });

  testWidgets('choosing Auto moves the fare and the booking carries the auto fare config and type', (tester) async {
    final api = await openConfirm(tester);

    await tester.tap(find.byKey(const Key('vehicle-auto')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('vehicle-auto')), matching: find.byKey(const Key('fare-range'))), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('vehicle-sedan')), matching: find.byKey(const Key('fare-range'))), findsNothing);

    await tester.tap(find.text('Book ride'));
    await tester.pumpAndSettle();

    final req = api.created.single;
    expect(req.vehicleType, VehicleType.auto);
    expect(req.fareConfigId, 'fc-auto');
    expect(req.paymentMethod, PaymentMethod.cash);
    expect(find.text('Finding your driver'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('out-of-area drop shows the notice but still allows booking', (tester) async {
    await openConfirm(tester, estimate: 'fare_estimate_drop_outside.json');

    expect(find.byKey(const Key('out-of-area')), findsOneWidget);
    expect(find.textContaining('outside our service area'), findsOneWidget);
    expect(find.text('₹4611 – ₹5339'), findsOneWidget);
    final book = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Book ride'));
    expect(book.onPressed, isNotNull);
  });

  testWidgets('Pay online → Book posts the estimate fare_config_id and online, then shows Finding',
      (tester) async {
    final sockets = SocketHarness();
    final api = await openConfirm(tester, sockets: sockets);
    sockets.connect();

    await tester.tap(find.text('Pay online'));
    await tester.pump();
    await tester.tap(find.text('Book ride'));
    await tester.pumpAndSettle();

    final req = api.created.single;
    expect(req.paymentMethod, PaymentMethod.online);
    expect(req.vehicleType, VehicleType.sedan);
    expect(req.fareConfigId, fixture('fare_estimate.json')['fare_config_id']);
    expect(req.pickup.address, 'Current location');
    expect(req.pickup.lat, cp.lat);
    expect(req.pickup.lng, cp.lng);
    expect(req.drop.address, 'India Gate');
    expect(find.text('Finding your driver'), findsOneWidget);
    // Subscribed to the new ride over the socket.
    expect(sockets.socket!.emitted.last.event, 'rider:subscribe');
    expect(sockets.socket!.emitted.last.data, {'ride_id': api.activeRide!.id});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ROUTING_UNAVAILABLE shows the server message with Retry; Book disabled', (tester) async {
    final api = FakeRideApi()
      ..estimateError = const ApiException(
          code: 'ROUTING_UNAVAILABLE', message: 'Route could not be calculated. Try again.', statusCode: 503);
    await openConfirm(tester, rides: api);

    expect(find.text('Route could not be calculated. Try again.'), findsOneWidget);
    final book = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Book ride'));
    expect(book.onPressed, isNull);

    api
      ..estimateError = null
      ..estimateJson = fixture('fare_estimate.json');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('₹94 – ₹109'), findsOneWidget);
    expect(api.estimateCalls, 2);
  });

  testWidgets('FARE_CONFIG_INVALID refreshes the estimate and explains', (tester) async {
    final api = FakeRideApi()
      ..createError = const ApiException(
          code: 'FARE_CONFIG_INVALID', message: 'Fare has changed. Please get a new estimate.', statusCode: 422);
    await openConfirm(tester, rides: api);

    await tester.tap(find.text('Book ride'));
    await tester.pumpAndSettle();

    expect(api.created, hasLength(1));
    expect(api.estimateCalls, 2);
    expect(find.text('Fares were updated. Here is a fresh estimate.'), findsOneWidget);
    expect(find.text('Confirm your ride'), findsOneWidget);
  });

  testWidgets('OUTSIDE_SERVICE_AREA shows the server message and stays on Confirm', (tester) async {
    final api = FakeRideApi()
      ..createError = const ApiException(
          code: 'OUTSIDE_SERVICE_AREA', message: 'Pickup is outside our service area', statusCode: 422);
    await openConfirm(tester, rides: api);

    await tester.tap(find.text('Book ride'));
    await tester.pumpAndSettle();

    expect(find.text('Pickup is outside our service area'), findsOneWidget);
    expect(find.text('Confirm your ride'), findsOneWidget);
  });
}
