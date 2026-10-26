import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

class FakePush implements PushTokenSource {
  FakePush(this.token);

  final String? token;
  final refreshes = StreamController<String>.broadcast();

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;
}

Map<String, dynamic> get riderJson =>
    fixture('otp_verify_rider.json')['user'] as Map<String, dynamic>;

({ProviderContainer container, FakeAdapter adapter, MemoryTokenStore store}) setup(
  FakeRoute Function(dynamic o) handler, {
  AuthTokens? tokens,
  String? fcm = 'fcm-1',
  FakePush? push,
}) {
  final adapter = FakeAdapter(handler);
  final store = MemoryTokenStore(tokens);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
      tokenStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((ref) => ApiClient(
            config: ref.watch(appConfigProvider),
            tokens: store,
            adapter: adapter,
            onSessionExpired: () => ref.read(sessionProvider.notifier).expire(),
          )),
      pushTokenSourceProvider.overrideWithValue(push ?? FakePush(fcm)),
      appVersionProvider.overrideWith((ref) async => '0.1.0+1'),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, adapter: adapter, store: store);
}

Future<void> settle() => pumpEventQueue();

void main() {
  const saved = AuthTokens(accessToken: 'a1', refreshToken: 'r1');

  test('starts unknown; restore without tokens → logged out, no network', () async {
    final s = setup((_) => (status: 500, body: null));
    expect(s.container.read(sessionProvider), isA<SessionUnknown>());

    await s.container.read(sessionProvider.notifier).restore();

    expect(s.container.read(sessionProvider), isA<SessionLoggedOut>());
    expect(s.adapter.calls, isEmpty);
  });

  test('restore with tokens → GET /me → logged in, FCM token registered', () async {
    final s = setup((o) => switch (o.path) {
          '/me' => (status: 200, body: riderJson),
          _ => (status: 204, body: null),
        }, tokens: saved);

    await s.container.read(sessionProvider.notifier).restore();
    await settle();

    final state = s.container.read(sessionProvider);
    expect(state, isA<SessionLoggedIn>());
    expect((state as SessionLoggedIn).user.id, riderJson['id']);
    expect(s.adapter.calls.map((c) => '${c.method} ${c.path}'), ['GET /me', 'POST /me/fcm-token']);
    expect(s.adapter.jsonBody(1), {'token': 'fcm-1'});
  });

  test('restore without an FCM token skips registration', () async {
    final s = setup((_) => (status: 200, body: riderJson), tokens: saved, fcm: null);
    await s.container.read(sessionProvider.notifier).restore();
    await settle();
    expect(s.adapter.calls.map((c) => c.path), ['/me']);
  });

  test('restore with a rejected refresh token → logged out, tokens cleared', () async {
    final s = setup((_) => apiError(401, 'UNAUTHORIZED', 'expired'), tokens: saved);

    await s.container.read(sessionProvider.notifier).restore();

    expect(s.container.read(sessionProvider), isA<SessionLoggedOut>());
    expect(await s.store.read(), isNull);
  });

  test('restore rethrows network errors so Splash can retry', () async {
    final s = setup((_) => apiError(503, 'STORAGE_UNAVAILABLE', 'down'), tokens: saved);
    await expectLater(s.container.read(sessionProvider.notifier).restore(), throwsA(isA<ApiException>()));
    expect(s.container.read(sessionProvider), isA<SessionUnknown>());
    expect(await s.store.read(), isNotNull);
  });

  test('verifyOtp stores tokens, sends device.fcm_token and logs in', () async {
    final s = setup((_) => (status: 200, body: fixture('otp_verify_rider.json')));

    final user = await s.container
        .read(sessionProvider.notifier)
        .verifyOtp(phone: '+919800000002', code: '123456', role: LoginRole.rider);

    expect(user.needsName, isTrue);
    expect(s.container.read(sessionProvider), isA<SessionLoggedIn>());
    expect((await s.store.read())!.accessToken, 'test-access-token');
    expect((s.adapter.jsonBody(0) as Map)['device'],
        {'platform': 'android', 'fcm_token': 'fcm-1', 'app_version': '0.1.0+1'});
  });

  test('token refresh while logged in is posted to /me/fcm-token', () async {
    final push = FakePush(null);
    final s = setup((o) => o.path == '/me' ? (status: 200, body: riderJson) : (status: 204, body: null),
        tokens: saved, push: push);
    await s.container.read(sessionProvider.notifier).restore();

    push.refreshes.add('rotated-token');
    await settle();

    expect(s.adapter.calls.last.path, '/me/fcm-token');
    expect(s.adapter.jsonBody(s.adapter.calls.length - 1), {'token': 'rotated-token'});
  });

  test('logout clears tokens even when the request fails', () async {
    final s = setup((_) => apiError(500, 'INTERNAL', 'boom'), tokens: saved);
    s.container.read(sessionProvider.notifier).setUser(User.fromJson(riderJson));

    await s.container.read(sessionProvider.notifier).logout();

    expect(s.adapter.calls.single.path, '/auth/logout');
    expect(s.container.read(sessionProvider), isA<SessionLoggedOut>());
    expect(await s.store.read(), isNull);
  });

  test('deleteAccount keeps the session on 409 and clears it on success', () async {
    var status = 409;
    final s = setup(
        (_) => status == 409 ? apiError(409, 'ACTIVE_RIDE', 'Finish your ride first') : (status: 204, body: null),
        tokens: saved);
    final session = s.container.read(sessionProvider.notifier)..setUser(User.fromJson(riderJson));

    await expectLater(session.deleteAccount(), throwsA(isA<ApiException>()));
    expect(s.container.read(sessionProvider), isA<SessionLoggedIn>());

    status = 204;
    await session.deleteAccount();
    expect(s.container.read(sessionProvider), isA<SessionLoggedOut>());
    expect(await s.store.read(), isNull);
  });
}
