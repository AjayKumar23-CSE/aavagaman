import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/alerts/ride_alert.dart';
import 'package:rider/src/alerts/ride_alert_listener.dart';

import 'helpers.dart';

class RecordingRideAlert implements RideAlert {
  int prepared = 0;
  final announced = <({RideAlertKind kind, String title, String body, bool inForeground})>[];

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<void> announce(RideAlertKind kind, {required String title, required String body, required bool inForeground}) async =>
      announced.add((kind: kind, title: title, body: body, inForeground: inForeground));
}

Ride requestedRide() => rideFrom('ride_requested.json', (j) {
      j['requested_at'] = DateTime.now().toUtc().subtract(const Duration(seconds: 10)).toIso8601String();
    });

Future<({FakeRideApi api, SocketHarness sockets, RecordingRideAlert alert})> launch(WidgetTester tester, Ride? ride) async {
  tallScreen(tester);
  final api = FakeRideApi()..activeRide = ride;
  final sockets = SocketHarness();
  final alert = RecordingRideAlert();
  await tester.pumpWidget(testApp(
    auth: FakeAuthApi(),
    me: FakeMeApi(rider(name: 'Asha')),
    tokens: saved,
    rides: api,
    sockets: sockets,
    overrides: [rideAlertProvider.overrideWithValue(alert)],
  ));
  await tester.pumpAndSettle();
  sockets.connect();
  await tester.pumpAndSettle();
  return (api: api, sockets: sockets, alert: alert);
}

void main() {
  testWidgets('driver accepts, then arrives: one chime each with the driver name', (tester) async {
    final h = await launch(tester, requestedRide());
    final id = h.api.activeRide!.id;
    expect(h.alert.announced, isEmpty, reason: 'opening the app on a waiting ride is quiet');

    h.api.activeRide = rideFrom('ride_accepted_rider_view.json', (j) {
      j['id'] = id;
      j['accepted_at'] = DateTime.now().toUtc().toIso8601String();
    });
    h.sockets.emit('ride:status', fixture('ws_ride_status_accepted_rider.json')..['ride_id'] = id);
    await tester.pumpAndSettle();

    expect(h.alert.announced, hasLength(1));
    expect(h.alert.announced.single.kind, RideAlertKind.accepted);
    expect(h.alert.announced.single.title, 'Driver on the way');
    expect(h.alert.announced.single.body, 'Phase Two Driver accepted your ride.');
    expect(h.alert.announced.single.inForeground, isTrue);

    h.api.activeRide = rideFrom('ride_arrived_rider_view.json', (j) => j['id'] = id);
    h.sockets.emit('ride:status', fixture('ws_ride_status_arrived_rider.json')..['ride_id'] = id);
    await tester.pumpAndSettle();

    expect(h.alert.announced.map((a) => a.kind), [RideAlertKind.accepted, RideAlertKind.arrived]);
    expect(h.alert.announced.last.title, 'Your driver has arrived');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening the app on an already accepted ride does not ring', (tester) async {
    final h = await launch(tester, rideFrom('ride_accepted_rider_view.json', (j) {
      j['accepted_at'] = DateTime.now().toUtc().toIso8601String();
    }));
    expect(find.text('Your driver is on the way'), findsOneWidget);
    expect(h.alert.announced, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
