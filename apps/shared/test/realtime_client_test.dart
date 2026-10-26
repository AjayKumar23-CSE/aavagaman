import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:ride_shared/testing.dart';

import 'fake_adapter.dart';

({RealtimeClient client, FakeRealtimeSocket Function() socket, List<String> reauths}) build({
  String token = 'tok-1',
  Future<String?> Function(String stale)? reauth,
}) {
  FakeRealtimeSocket? created;
  final reauths = <String>[];
  var current = token;
  final client = RealtimeClient(
    apiBaseUrl: 'http://api.test',
    accessToken: () async => current,
    reauthenticate: (stale) async {
      reauths.add(stale);
      if (reauth != null) return reauth(stale);
      current = 'tok-2';
      return current;
    },
    socketFactory: (url, auth) => created = FakeRealtimeSocket(url, auth),
    ackTimeout: const Duration(seconds: 2),
  );
  return (client: client, socket: () => created!, reauths: reauths);
}

void main() {
  test('connects to /rt with the current access token and reports status', () async {
    final b = build();
    final statuses = <RealtimeStatus>[];
    b.client.statusChanges.listen(statuses.add);
    expect(b.client.status, RealtimeStatus.disconnected);

    b.client.connect();
    await pumpEventQueue();
    final s = b.socket();
    expect(s.url, 'http://api.test/rt');
    expect(s.handshakes.single, {'token': 'tok-1'});
    expect(b.client.status, RealtimeStatus.connecting);

    s.serverConnect();
    expect(b.client.status, RealtimeStatus.connected);
    expect(b.client.isConnected, isTrue);

    s.serverDrop();
    expect(b.client.status, RealtimeStatus.reconnecting);
    s.serverEmit('reconnect_attempt', 1);
    s.serverConnect();
    await pumpEventQueue();
    expect(statuses, [
      RealtimeStatus.connecting,
      RealtimeStatus.connected,
      RealtimeStatus.reconnecting,
      RealtimeStatus.connected,
    ]);

    b.client.disconnect();
    expect(b.client.status, RealtimeStatus.disconnected);
    expect(s.disconnectCalls, 1);
    b.client.dispose();
    expect(s.disposed, isTrue);
  });

  test('UNAUTHORIZED handshake → refresh via the session path → reconnect with the new token', () {
    fakeAsync((async) {
      final b = build();
      b.client.connect();
      async.flushMicrotasks();
      final s = b.socket();
      expect(s.handshakes.last, {'token': 'tok-1'});

      s.serverReject({'message': 'UNAUTHORIZED'});
      async.flushMicrotasks();
      expect(b.reauths, ['tok-1']);
      expect(b.client.status, RealtimeStatus.reconnecting);

      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();
      expect(s.connectCalls, 2);
      expect(s.handshakes.last, {'token': 'tok-2'});
      s.serverConnect();
      expect(b.client.status, RealtimeStatus.connected);
      b.client.dispose();
    });
  });

  test('session over (refresh returns null) → stops retrying, disconnected', () {
    fakeAsync((async) {
      final b = build(reauth: (_) async => null);
      b.client.connect();
      async.flushMicrotasks();
      final s = b.socket();
      s.serverReject({'message': 'UNAUTHORIZED'});
      async.flushMicrotasks();
      expect(b.client.status, RealtimeStatus.disconnected);
      async.elapse(const Duration(minutes: 1));
      expect(s.connectCalls, 1);
      b.client.dispose();
    });
  });

  test('other handshake errors retry with backoff', () {
    fakeAsync((async) {
      final b = build();
      b.client.connect();
      async.flushMicrotasks();
      final s = b.socket();
      s.serverReject({'message': 'Server is restarting'});
      async.flushMicrotasks();
      expect(b.reauths, isEmpty);
      expect(b.client.status, RealtimeStatus.reconnecting);
      async.elapse(const Duration(seconds: 3));
      expect(s.connectCalls, 2);
      b.client.dispose();
    });
  });

  test('typed streams parse the real server payloads', () async {
    final b = build();
    b.client.connect();
    await pumpEventQueue();
    final s = b.socket()..serverConnect();

    final offers = <RideOffer>[];
    final statuses = <RideStatusEvent>[];
    final positions = <DriverPosition>[];
    final expired = <String>[];
    final noDriver = <String>[];
    final payments = <PaymentStatusEvent>[];
    b.client.offers.listen(offers.add);
    b.client.rideStatus.listen(statuses.add);
    b.client.driverPositions.listen(positions.add);
    b.client.offerExpired.listen(expired.add);
    b.client.noDriver.listen(noDriver.add);
    b.client.paymentStatus.listen(payments.add);

    s.serverEmit('ride:offer', fixture('ws_ride_offer.json'));
    s.serverEmit('ride:status', fixture('ws_ride_status_accepted_rider.json'));
    s.serverEmit('driver:position', fixture('ws_driver_position.json'));
    s.serverEmit('ride:offer:expired', {'ride_id': 'r-exp'});
    s.serverEmit('ride:no_driver', {'ride_id': 'r-nd'});
    s.serverEmit('payment:status', fixture('ws_payment_status_paid_rider.json'));
    // Malformed payloads are dropped, not thrown.
    s.serverEmit('ride:status', {'ride_id': 'x', 'status': 'WHATEVER'});
    s.serverEmit('ride:offer', 'garbage');
    await pumpEventQueue();

    expect(offers.single.distanceToPickupM, 148);
    expect(statuses.single.tripOtp, isNotNull);
    expect(positions.single.etaS, 25);
    expect(expired, ['r-exp']);
    expect(noDriver, ['r-nd']);
    expect(payments.single.isPaid, isTrue);
    expect(payments.single.isCash, isTrue);
    expect(payments.single.rideId, hasLength(36));
    b.client.dispose();
  });

  group('emitWithAck', () {
    test('driver:location ok, accept returns the ride, errors become ApiException', () async {
      final b = build();
      b.client.connect();
      await pumpEventQueue();
      final s = b.socket()..serverConnect();
      s.ackHandler = (event, data) => switch (event) {
            'driver:offer:accept' when data['ride_id'] == 'good' => fixture('ws_ack_accept.json'),
            'driver:offer:accept' => fixture('ws_ack_accept_not_valid.json'),
            'driver:location' when data['lat'] is String => fixture('ws_ack_validation_error.json'),
            'rider:subscribe' when data['ride_id'] == 'nope' => fixture('ws_ack_subscribe_not_found.json'),
            _ => fixture('ws_ack_location_ok.json'),
          };

      await b.client.sendDriverLocation(const DriverFix(lat: 28.6, lng: 77.2, heading: 90));
      expect(s.emitted.last.event, 'driver:location');
      expect(s.emitted.last.data, {'lat': 28.6, 'lng': 77.2, 'heading': 90});

      final ride = await b.client.acceptOffer('good');
      expect(ride.status, RideStatus.accepted);
      expect(ride.rider!.name, 'Phase Two Rider');
      expect(s.emitted.last.data, {'ride_id': 'good'});

      await expectLater(
        b.client.acceptOffer('taken'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'OFFER_NOT_VALID')
            .having((e) => e.message, 'message', 'This ride is no longer available')),
      );
      await expectLater(
        b.client.subscribeRide('nope'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
      await b.client.rejectOffer('r1');
      await b.client.subscribeRide('r1');
      expect(s.emitted.map((e) => e.event).toList(), [
        'driver:location',
        'driver:offer:accept',
        'driver:offer:accept',
        'rider:subscribe',
        'driver:offer:reject',
        'rider:subscribe',
      ]);
      b.client.dispose();
    });

    test('fails fast with NETWORK_ERROR while disconnected', () async {
      final b = build();
      await expectLater(
        b.client.sendDriverLocation(const DriverFix(lat: 1, lng: 2)),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue)),
      );
      b.client.connect();
      await pumpEventQueue();
      // Connecting but not yet connected still counts as offline.
      await expectLater(b.client.subscribeRide('r'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR')));
      expect(b.socket().emitted, isEmpty);
      b.client.dispose();
    });

    test('a lost acknowledgement times out', () {
      fakeAsync((async) {
        final b = build();
        b.client.connect();
        async.flushMicrotasks();
        final s = b.socket()..serverConnect();
        s.autoAck = false;
        Object? error;
        b.client.rejectOffer('r1').catchError((Object e) {
          error = e;
        });
        async.elapse(const Duration(seconds: 3));
        expect(error, isA<ApiException>().having((e) => e.code, 'code', 'ACK_TIMEOUT'));
        b.client.dispose();
      });
    });
  });

  test('realtimeClientProvider wires the API client token and refresh', () async {
    final adapter = FakeAdapter((o) => o.path == '/auth/refresh'
        ? (status: 200, body: {'access_token': 'a2', 'refresh_token': 'r2'})
        : (status: 200, body: {}));
    final store = MemoryTokenStore(const AuthTokens(accessToken: 'a1', refreshToken: 'r1'));
    final container = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
      tokenStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((ref) => ApiClient(
            config: ref.watch(appConfigProvider),
            tokens: store,
            adapter: adapter,
          )),
    ]);
    addTearDown(container.dispose);
    // Riverpod 3 pauses providers nobody listens to, so attach a listener first.
    final sub = container.listen(realtimeStatusProvider, (_, _) {});
    addTearDown(sub.close);
    final client = container.read(realtimeClientProvider);
    expect(client.apiBaseUrl, 'http://api.test');
    expect(await client.accessToken(), 'a1');
    expect(await client.reauthenticate('a1'), 'a2');
    expect((await store.read())!.refreshToken, 'r2');
    // Already rotated by someone else → no second network call.
    expect(await client.reauthenticate('a1'), 'a2');
    expect(adapter.calls.where((c) => c.path == '/auth/refresh').length, 1);
    expect(await container.read(realtimeStatusProvider.future), RealtimeStatus.disconnected);
  });
}
