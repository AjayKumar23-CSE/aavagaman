import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test');
const initial = AuthTokens(accessToken: 'a1', refreshToken: 'r1');

void main() {
  test('refreshTokens rotates once even when REST and the socket ask concurrently', () async {
    var rotations = 0;
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/refresh') {
        rotations++;
        return (status: 200, body: {'access_token': 'a$rotations+', 'refresh_token': 'r$rotations+'});
      }
      return o.headers['Authorization'] == 'Bearer a1'
          ? (status: 401, body: {'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}})
          : (status: 200, body: {'ok': true});
    });
    final store = MemoryTokenStore(initial);
    final api = ApiClient(config: config, tokens: store, adapter: adapter);

    final results = await Future.wait([
      api.refreshTokens(staleAccessToken: 'a1'),
      api.dio.get('/me').then((r) => r.statusCode.toString()),
      api.refreshTokens(staleAccessToken: 'a1'),
    ]);

    expect(rotations, 1);
    expect(results[0], 'a1+');
    expect(results[1], '200');
    expect(results[2], 'a1+');
    expect((await store.read())!.refreshToken, 'r1+');
  });

  test('refreshTokens skips the network when the store already moved on', () async {
    final adapter = FakeAdapter((_) => (status: 500, body: null));
    final store = MemoryTokenStore(const AuthTokens(accessToken: 'a2', refreshToken: 'r2'));
    final api = ApiClient(config: config, tokens: store, adapter: adapter);
    expect(await api.refreshTokens(staleAccessToken: 'a1'), 'a2');
    expect(adapter.calls, isEmpty);
  });

  test('refreshTokens: rejected refresh clears tokens, fires onSessionExpired, returns null',
      () async {
    var expired = false;
    final adapter = FakeAdapter((_) => apiError(401, 'UNAUTHORIZED', 'revoked'));
    final store = MemoryTokenStore(initial);
    final api = ApiClient(
      config: config,
      tokens: store,
      adapter: adapter,
      onSessionExpired: () => expired = true,
    );
    expect(await api.refreshTokens(staleAccessToken: 'a1'), isNull);
    expect(expired, isTrue);
    expect(await store.read(), isNull);
    // No session at all → null without a request.
    expect(await api.refreshTokens(), isNull);
  });

  test('refreshTokens: network failure keeps the tokens and throws', () async {
    final adapter = FakeAdapter((_) => (status: 503, body: {'error': {'code': 'DOWN', 'message': 'down'}}));
    final store = MemoryTokenStore(initial);
    final api = ApiClient(config: config, tokens: store, adapter: adapter);
    await expectLater(api.refreshTokens(staleAccessToken: 'a1'), throwsA(isA<ApiException>()));
    expect((await store.read())!.accessToken, 'a1');
    expect(await api.accessToken(), 'a1');
  });
}
