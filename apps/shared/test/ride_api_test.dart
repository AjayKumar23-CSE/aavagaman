import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test');
const tokens = AuthTokens(accessToken: 'a1', refreshToken: 'r1');
const cp = RidePlace(lat: 28.6315, lng: 77.2167, address: 'Connaught Place, New Delhi');
const indiaGate = RidePlace(lat: 28.6129, lng: 77.2295, address: 'India Gate, New Delhi');

RideApi api(FakeAdapter adapter) =>
    RideApi(ApiClient(config: config, tokens: MemoryTokenStore(tokens), adapter: adapter));

FakeRoute fromFixture(String name, [int status = 200]) =>
    (status: status, body: fixture(name));

void main() {
  group('rider', () {
    test('estimate posts both places and parses the response', () async {
      final adapter = FakeAdapter((_) => fromFixture('fare_estimate.json'));
      final e = await api(adapter).estimate(pickup: cp, drop: indiaGate);

      expect(e.fareMin, 94);
      expect(e.fareConfigId, isNotEmpty);
      final call = adapter.calls.single;
      expect('${call.method} ${call.uri}', 'POST http://api.test/v1/fare/estimate');
      expect(call.headers['Authorization'], 'Bearer a1');
      expect(adapter.jsonBody(0), {'pickup': cp.toJson(), 'drop': indiaGate.toJson()});
    });

    test('estimate surfaces 503 ROUTING_UNAVAILABLE', () async {
      final adapter = FakeAdapter(
          (_) => apiError(503, 'ROUTING_UNAVAILABLE', 'Route could not be calculated. Try again.'));
      await expectLater(
        api(adapter).estimate(pickup: cp, drop: indiaGate),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'ROUTING_UNAVAILABLE')
            .having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('nearby passes lat/lng as query parameters', () async {
      final adapter = FakeAdapter((_) => (status: 200, body: fixtureList('drivers_nearby.json')));
      final cars = await api(adapter).nearby(lat: 28.6315, lng: 77.2167);

      expect(cars.single.driverId, hasLength(16));
      final uri = adapter.calls.single.uri;
      expect(uri.path, '/v1/drivers/nearby');
      expect(uri.queryParameters, {'lat': '28.6315', 'lng': '77.2167'});
    });

    test('create sends the SPEC body and parses the REQUESTED ride', () async {
      final adapter = FakeAdapter((_) => fromFixture('ride_requested.json', 201));
      final ride = await api(adapter).create(
        pickup: cp,
        drop: indiaGate,
        fareConfigId: 'cfg-1',
        paymentMethod: PaymentMethod.online,
      );

      expect(ride.status, RideStatus.requested);
      expect(adapter.jsonBody(0), {
        'pickup': cp.toJson(),
        'drop': indiaGate.toJson(),
        'fare_config_id': 'cfg-1',
        'vehicle_type': 'sedan',
        'payment_method': 'online',
      });
    });

    test('create errors keep the server code (real bodies)', () async {
      for (final (name, code, status) in [
        ('rides_create_outside_service_area.json', 'OUTSIDE_SERVICE_AREA', 422),
        ('rides_create_active_ride_exists.json', 'ACTIVE_RIDE_EXISTS', 409),
        ('rides_create_fare_config_invalid.json', 'FARE_CONFIG_INVALID', 422),
      ]) {
        final adapter = FakeAdapter((_) => fromFixture(name, status));
        await expectLater(
          api(adapter).create(pickup: cp, drop: indiaGate, fareConfigId: 'x', paymentMethod: PaymentMethod.cash),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.statusCode, 'status', status)
              .having((e) => e.message, 'message', isNotEmpty)),
        );
      }
    });

    test('active returns null on 404 NO_ACTIVE_RIDE and the ride otherwise', () async {
      final none = FakeAdapter((_) => fromFixture('rides_active_404.json', 404));
      expect(await api(none).active(), isNull);
      expect(none.calls.single.uri.path, '/v1/rides/active');

      final some = FakeAdapter((_) => fromFixture('rides_active_requested.json'));
      expect((await api(some).active())!.status, RideStatus.requested);
    });

    test('active rethrows other errors', () async {
      final adapter = FakeAdapter((_) => apiError(500, 'INTERNAL', 'boom'));
      await expectLater(api(adapter).active(), throwsA(isA<ApiException>()));
    });

    test('get and cancel use the ride id; cancel omits a null reason', () async {
      final adapter = FakeAdapter((o) => o.path.endsWith('/cancel')
          ? fromFixture('ride_cancelled_by_rider.json')
          : fromFixture('ride_accepted_rider_view.json'));
      final a = api(adapter);
      final r = await a.get('50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b');
      expect(r.driver!.name, 'Phase Two Driver');
      final c = await a.cancel('50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b');
      expect(c.status, RideStatus.cancelled);
      await a.cancel('50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b', reason: 'Changed plans');

      expect(adapter.calls.map((c) => '${c.method} ${c.path}'), [
        'GET /rides/50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b',
        'POST /rides/50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b/cancel',
        'POST /rides/50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b/cancel',
      ]);
      expect(adapter.jsonBody(1), <String, dynamic>{});
      expect(adapter.jsonBody(2), {'reason': 'Changed plans'});
    });

    test('cancel after accept → 409 RIDE_NOT_CANCELLABLE (real body)', () async {
      final adapter = FakeAdapter((_) => fromFixture('rides_cancel_not_cancellable.json', 409));
      await expectLater(
        api(adapter).cancel('r1'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'RIDE_NOT_CANCELLABLE')
            .having((e) => e.message, 'message', contains('no longer be cancelled'))),
      );
    });
  });

  group('driver', () {
    test('online / offline / location bodies and 204 handling', () async {
      final adapter = FakeAdapter((_) => (status: 204, body: null));
      final a = api(adapter);
      await a.driverOnline(lat: 28.63, lng: 77.21);
      await a.driverLocation(const DriverFix(lat: 28.63, lng: 77.21, heading: 90, speed: 5, accuracy: 8, ts: 1));
      await a.driverOffline();

      expect(adapter.calls.map((c) => '${c.method} ${c.path}'),
          ['POST /driver/online', 'POST /driver/location', 'POST /driver/offline']);
      expect(adapter.jsonBody(0), {'lat': 28.63, 'lng': 77.21});
      expect(adapter.jsonBody(1),
          {'lat': 28.63, 'lng': 77.21, 'heading': 90, 'speed': 5, 'accuracy': 8, 'ts': 1});
    });

    test('online 403 NOT_ELIGIBLE, offline 409 ON_TRIP, location 409 DRIVER_OFFLINE', () async {
      final notEligible = FakeAdapter(
          (_) => apiError(403, 'NOT_ELIGIBLE', 'Your account is not approved to go online'));
      await expectLater(api(notEligible).driverOnline(lat: 1, lng: 2),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NOT_ELIGIBLE')));

      final onTrip = FakeAdapter((_) => fromFixture('driver_offline_on_trip.json', 409));
      await expectLater(api(onTrip).driverOffline(),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ON_TRIP')));

      final offline = FakeAdapter((_) => apiError(409, 'DRIVER_OFFLINE', 'You are offline. Go online again.'));
      await expectLater(api(offline).driverLocation(const DriverFix(lat: 1, lng: 2)),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'DRIVER_OFFLINE')));
    });

    test('driverActive null on 404; accept parses the driver view; reject 204', () async {
      final none = FakeAdapter((_) => fromFixture('driver_rides_active_404.json', 404));
      expect(await api(none).driverActive(), isNull);
      expect(none.calls.single.uri.path, '/v1/driver/rides/active');

      final adapter = FakeAdapter((o) => o.path.endsWith('/accept')
          ? fromFixture('ride_accepted_driver_view.json')
          : (status: 204, body: null));
      final a = api(adapter);
      final ride = await a.driverAccept('50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b');
      expect(ride.rider!.name, 'Phase Two Rider');
      expect(ride.tripOtp, isNull);
      await a.driverReject('r2');
      expect(adapter.calls.map((c) => '${c.method} ${c.path}'), [
        'POST /driver/rides/50e8fbe1-f0ee-4ec4-b7e8-b975a61db20b/accept',
        'POST /driver/rides/r2/reject',
      ]);
    });

    test('accept 409 OFFER_NOT_VALID (real body)', () async {
      final adapter = FakeAdapter((_) => fromFixture('driver_accept_409.json', 409));
      await expectLater(api(adapter).driverAccept('r1'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'OFFER_NOT_VALID')));
    });
  });
}
