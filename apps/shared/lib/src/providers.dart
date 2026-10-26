import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/driver_api.dart';
import 'api/me_api.dart';
import 'api/payments_api.dart';
import 'api/ride_api.dart';
import 'api/token_store.dart';
import 'config/app_config.dart';
import 'places/places_api.dart';
import 'push/push_token_source.dart';
import 'realtime/realtime_client.dart';
import 'safety/sos_flow.dart';
import 'session/session.dart';

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(appConfigProvider),
    tokens: ref.watch(tokenStoreProvider),
    onSessionExpired: () => ref.read(sessionProvider.notifier).expire(),
  ),
);

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

final meApiProvider = Provider<MeApi>((ref) => MeApi(ref.watch(apiClientProvider)));

final driverApiProvider = Provider<DriverApi>((ref) => DriverApi(ref.watch(apiClientProvider)));

final rideApiProvider = Provider<RideApi>((ref) => RideApi(ref.watch(apiClientProvider)));

final paymentsApiProvider =
    Provider<PaymentsApi>((ref) => PaymentsApi(ref.watch(apiClientProvider)));

/// SOS helper (dialer + `POST /rides/:id/sos`); apps override the launcher in tests.
final sosFlowProvider = Provider<SosFlow>((ref) => SosFlow(api: ref.watch(rideApiProvider)));

/// Google Places when `GOOGLE_MAPS_API_KEY` is set, otherwise [NoPlacesApi].
final placesApiProvider = Provider<PlacesApi>((ref) {
  final key = ref.watch(appConfigProvider).googleMapsApiKey;
  return key.isEmpty ? const NoPlacesApi() : GooglePlacesApi(apiKey: key);
});

/// One Socket.io connection per app. Apps call `connect()` once logged in
/// and `disconnect()` on logout; token refresh goes through the API client's
/// single-flight refresher.
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final api = ref.watch(apiClientProvider);
  final client = RealtimeClient(
    apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    accessToken: api.accessToken,
    reauthenticate: (stale) => api.refreshTokens(staleAccessToken: stale),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Connected / reconnecting / disconnected, for status chips.
final realtimeStatusProvider = StreamProvider<RealtimeStatus>((ref) {
  final client = ref.watch(realtimeClientProvider);
  final controller = StreamController<RealtimeStatus>();
  controller.add(client.status);
  final sub = client.statusChanges.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

final pushTokenSourceProvider = Provider<PushTokenSource>((ref) => FirebasePushTokenSource());

/// `version+build` from the platform, sent as `device.app_version`.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (e) {
    debugPrint('App version unavailable ($e)');
    return null;
  }
});
