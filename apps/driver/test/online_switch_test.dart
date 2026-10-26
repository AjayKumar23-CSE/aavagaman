import 'package:driver/src/presence/permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'helpers.dart';

typedef Harness = ({FakeRideApi rides, FakeLocationFeed feed, FakePermissionGate gate, SocketHarness sockets});

Future<Harness> launchHome(
  WidgetTester tester, {
  FakeRideApi? rides,
  FakePermissionGate? gate,
  bool connectSocket = true,
}) async {
  tallScreen(tester);
  final h = (
    rides: rides ?? FakeRideApi(),
    feed: FakeLocationFeed(),
    gate: gate ?? FakePermissionGate(),
    sockets: SocketHarness(),
  );
  await tester.pumpWidget(testApp(
    driver: FakeDriverApi(approvedProfile()),
    rides: h.rides,
    feed: h.feed,
    permissions: h.gate,
    sockets: h.sockets,
  ));
  await tester.pumpAndSettle();
  if (connectSocket) {
    h.sockets.connect();
    await tester.pumpAndSettle();
  }
  return h;
}

SwitchListTile onlineSwitch(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(const Key('online-switch')));

String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('presence-status'))).data!;

void main() {
  testWidgets('starts offline with the switch enabled and the earnings placeholder', (tester) async {
    await launchHome(tester);
    expect(status(tester), "You're offline");
    expect(onlineSwitch(tester).value, isFalse);
    expect(onlineSwitch(tester).onChanged, isNotNull);
    expect(find.text("Today's earnings"), findsOneWidget);
    expect(find.text('₹0 · 0 trips'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home opens on a map at the driver; the car appears once online and follows new fixes', (tester) async {
    final h = await launchHome(tester);
    // Offline: the map sits on the phone's own fix, with no car (riders can't see this driver).
    expect(find.textContaining('map 28.6325,77.2177'), findsOneWidget);
    expect(find.textContaining('car'), findsNothing);
    expect(find.byKey(const Key('locate')), findsOneWidget);

    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    // Online: the car shows at the go-online fix…
    expect(find.textContaining('map 28.6325,77.2177 car'), findsOneWidget);
    // …and moves with the next fix from the location service.
    h.feed.emit(const DriverFix(lat: 28.64, lng: 77.22, heading: 180, speed: 7, accuracy: 8, ts: 2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.textContaining('map 28.6400,77.2200 car'), findsOneWidget);

    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switch on: permissions → fix → POST /driver/online → service → driver:location every 4 s',
      (tester) async {
    final h = await launchHome(tester);

    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();

    expect(h.gate.ensureCalls, 1);
    expect(h.rides.onlineCalls.single, (lat: cpFix.lat, lng: cpFix.lng));
    expect(h.feed.startCalls, 1);
    expect(h.feed.notificationTitle, 'You are online');
    expect(status(tester), "You're online");
    expect(onlineSwitch(tester).value, isTrue);

    // Fixes stream in; a 150 m fix is dropped, an 8 m one is kept.
    h.feed.emit(const DriverFix(lat: 1, lng: 1, accuracy: 150));
    h.feed.emit(const DriverFix(lat: 28.64, lng: 77.22, heading: 180, speed: 7, accuracy: 8, ts: 2));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    final sent = h.sockets.socket!.emitted.where((e) => e.event == 'driver:location').toList();
    expect(sent, hasLength(1));
    expect(sent.single.data, {'lat': 28.64, 'lng': 77.22, 'heading': 180, 'speed': 7, 'accuracy': 8, 'ts': 2});
    expect(h.rides.locationCalls, isEmpty);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(h.sockets.socket!.emitted.where((e) => e.event == 'driver:location'), hasLength(2));

    // Switch off → POST /driver/offline, service stopped.
    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    expect(h.rides.offlineCalls, 1);
    expect(h.feed.stopCalls, 1);
    expect(status(tester), "You're offline");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('socket down: "Reconnecting…", REST fallback, re-online on reconnect', (tester) async {
    final h = await launchHome(tester);
    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    h.feed.emit(cpFix);

    h.sockets.socket!.serverDrop();
    await tester.pumpAndSettle();
    expect(status(tester), 'Reconnecting…');

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(h.rides.locationCalls, hasLength(1));
    expect(h.sockets.socket!.emitted.where((e) => e.event == 'driver:location'), isEmpty);

    // Server swept us offline meanwhile → 409 DRIVER_OFFLINE → /driver/online again.
    h.rides.locationError =
        const ApiException(code: 'DRIVER_OFFLINE', message: 'You are offline. Go online again.', statusCode: 409);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(h.rides.onlineCalls, hasLength(2));
    h.rides.locationError = null;

    // Socket back → status online and one more /driver/online.
    h.sockets.socket!.serverConnect();
    await tester.pumpAndSettle();
    expect(status(tester), "You're online");
    expect(h.rides.onlineCalls, hasLength(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('403 NOT_ELIGIBLE keeps the switch off and shows the server message', (tester) async {
    final rides = FakeRideApi()
      ..onlineError = const ApiException(
          code: 'NOT_ELIGIBLE', message: 'Your account is not approved to go online', statusCode: 403);
    final h = await launchHome(tester, rides: rides);

    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();

    expect(onlineSwitch(tester).value, isFalse);
    expect(status(tester), "You're offline");
    expect(find.text('Your account is not approved to go online'), findsOneWidget);
    expect(h.feed.startCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing background location blocks going online with a settings prompt', (tester) async {
    final h = await launchHome(tester, gate: FakePermissionGate({PermissionProblem.backgroundDenied}));

    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();

    expect(onlineSwitch(tester).value, isFalse);
    expect(find.textContaining('All the time'), findsOneWidget);
    expect(h.rides.onlineCalls, isEmpty);
    await tester.tap(find.text('Open settings'));
    expect(h.gate.openedAppSettings, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('denied notifications only warn; the driver still goes online', (tester) async {
    final h = await launchHome(tester, gate: FakePermissionGate({PermissionProblem.notificationsDenied}));
    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    expect(status(tester), "You're online");
    expect(find.textContaining('Allow notifications'), findsOneWidget);
    expect(h.rides.onlineCalls, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with an active ride the trip screen owns Home; the switch is out of reach', (tester) async {
    final rides = FakeRideApi()..activeRide = rideFrom('ride_accepted_driver_view.json');
    await launchHome(tester, rides: rides);
    expect(find.text('Navigate to pickup'), findsOneWidget);
    expect(find.byKey(const Key('online-switch')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offline refused with 409 ON_TRIP keeps the driver online with the message', (tester) async {
    final rides = FakeRideApi()
      ..offlineError = const ApiException(
          code: 'ON_TRIP', message: 'Finish your ride before going offline', statusCode: 409);
    final h = await launchHome(tester, rides: rides);
    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    expect(status(tester), "You're online");

    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();
    expect(status(tester), "You're online");
    expect(onlineSwitch(tester).value, isTrue);
    expect(find.text('Finish your ride before going offline'), findsOneWidget);
    expect(h.feed.stopCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('first time online opens the battery guide with brand notes', (tester) async {
    tallScreen(tester);
    final sockets = SocketHarness();
    await tester.pumpWidget(testApp(
      driver: FakeDriverApi(approvedProfile()),
      rides: FakeRideApi(),
      feed: FakeLocationFeed(),
      sockets: sockets,
      batteryGuideSeen: false,
    ));
    await tester.pumpAndSettle();
    sockets.connect();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online-switch')));
    await tester.pumpAndSettle();

    expect(find.text('Keep ride requests coming'), findsOneWidget);
    expect(find.byKey(const Key('brand-note')), findsOneWidget);
    expect(find.textContaining('Xiaomi'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(status(tester), "You're online");
    await tester.pumpWidget(const SizedBox());
  });
}
