import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test');
const initial = AuthTokens(accessToken: 'a1', refreshToken: 'r1');

void main() {
  test('adds the bearer token', () async {
    final adapter = FakeAdapter((_) => (status: 200, body: {'ok': true}));
    final api = ApiClient(config: config, tokens: MemoryTokenStore(initial), adapter: adapter);

    await api.dio.get('/me');

    expect(adapter.calls.single.uri.toString(), 'http://api.test/v1/me');
    expect(adapter.calls.single.headers['Authorization'], 'Bearer a1');
  });

  test('refreshes once on 401 and retries with the rotated token', () async {
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/refresh') {
        return (status: 200, body: {'access_token': 'a2', 'refresh_token': 'r2'});
      }
      final ok = o.headers['Authorization'] == 'Bearer a2';
      return ok
          ? (status: 200, body: {'ok': true})
          : (status: 401, body: {'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}});
    });
    final store = MemoryTokenStore(initial);
    final api = ApiClient(config: config, tokens: store, adapter: adapter);

    final results = await Future.wait([api.dio.get('/me'), api.dio.get('/rides/active')]);

    expect(results.map((r) => r.statusCode), [200, 200]);
    expect(adapter.calls.where((c) => c.path == '/auth/refresh').length, 1);
    expect((await store.read())!.refreshToken, 'r2');
  });

  test('clears tokens and reports expiry when refresh is rejected', () async {
    var expired = false;
    final adapter = FakeAdapter((o) => (
          status: 401,
          body: {'error': {'code': 'UNAUTHORIZED', 'message': 'no'}},
        ));
    final store = MemoryTokenStore(initial);
    final api = ApiClient(
      config: config,
      tokens: store,
      adapter: adapter,
      onSessionExpired: () => expired = true,
    );

    await expectLater(api.dio.get('/me'), throwsA(isA<DioException>()));
    expect(expired, isTrue);
    expect(await store.read(), isNull);
  });

  test('health reads the report even on 503', () async {
    final adapter = FakeAdapter((_) => (
          status: 503,
          body: {'status': 'error', 'db': false, 'redis': true, 'osrm': true},
        ));
    final api = ApiClient(config: config, tokens: MemoryTokenStore(), adapter: adapter);

    final h = await api.health();

    expect(adapter.calls.single.uri.toString(), 'http://api.test/health');
    expect(h.ok, isFalse);
    expect(h.db, isFalse);
  });

  test('ApiException parses the SPEC error shape', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/rides'),
      response: Response(
        requestOptions: RequestOptions(path: '/rides'),
        statusCode: 409,
        data: {'error': {'code': 'RIDE_NOT_CANCELLABLE', 'message': 'Too late'}},
      ),
    );
    final ex = ApiException.fromDio(e);
    expect(ex.code, 'RIDE_NOT_CANCELLABLE');
    expect(ex.statusCode, 409);
  });
}
