import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import 'offers/offer_alert.dart';
import 'presence/location_feed.dart';
import 'presence/permissions.dart';
import 'prefs.dart';

export 'offers/offer_controller.dart' show offerProvider, OfferState;
export 'presence/presence_controller.dart' show presenceProvider, PresenceState, PresencePhase;
export 'trip/driver_ride.dart' show activeRideProvider, DriverRide;

// Core providers (config, tokens, API client, session, realtime) live in ride_shared.

/// `GET /driver/me` for the logged-in driver; null when logged out.
/// Errors are surfaced (Splash shows a retry) instead of auto-retried.
final driverProfileProvider = AsyncNotifierProvider<DriverProfileController, DriverProfile?>(
  DriverProfileController.new,
  retry: (_, _) => null,
);

class DriverProfileController extends AsyncNotifier<DriverProfile?> {
  @override
  Future<DriverProfile?> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.id : null));
    if (userId == null) return null;
    return ref.read(driverApiProvider).me();
  }

  /// Re-fetches without passing through a loading state, so screens (and
  /// router redirects) keep the current profile while polling. Throws
  /// [ApiException] on failure and keeps the previous value.
  Future<DriverProfile> refresh() async {
    final p = await ref.read(driverApiProvider).me();
    state = AsyncData(p);
    return p;
  }

  /// Retry after a failed initial load.
  void reload() => ref.invalidateSelf();

  void set(DriverProfile profile) => state = AsyncData(profile);
}

/// Keeps the `/rt` socket open while logged in (watched from `App`).
final realtimeConnectorProvider = Provider<void>((ref) {
  final client = ref.watch(realtimeClientProvider);
  void sync(SessionState s) {
    switch (s) {
      case SessionLoggedIn():
        client.connect();
      case SessionLoggedOut():
        client.disconnect();
      case SessionUnknown():
        break;
    }
  }

  ref.listen(sessionProvider, (_, s) => sync(s));
  sync(ref.read(sessionProvider));
});

final locationFeedProvider = Provider<LocationFeed>((ref) => BackgroundLocationFeed());

/// One fix for the home map while offline; once online the presence feed's
/// `lastFix` takes over. Null when location is off or not allowed yet.
final driverHereProvider = FutureProvider<DriverFix?>((ref) => ref.watch(locationFeedProvider).currentFix());

final permissionGateProvider = Provider<PermissionGate>((ref) => const AndroidPermissionGate());

/// Replaced by the audio implementation in `main()`; silent in tests.
final offerAlertProvider = Provider<OfferAlert>((ref) => const SilentOfferAlert());

final appPrefsProvider = Provider<AppPrefs>((ref) => SharedPrefsAppPrefs());

/// `Build.MANUFACTURER` (lower case) for the battery guide; null when unknown.
final deviceBrandProvider = FutureProvider<String?>((ref) => readDeviceBrand());

/// Whether the one-time battery-optimisation guide has been shown.
final batteryGuideSeenProvider = AsyncNotifierProvider<BatteryGuideSeen, bool>(BatteryGuideSeen.new);

class BatteryGuideSeen extends AsyncNotifier<bool> {
  static const key = 'battery_guide_seen';

  @override
  Future<bool> build() => ref.watch(appPrefsProvider).getBool(key);

  Future<void> markSeen() async {
    state = const AsyncData(true);
    await ref.read(appPrefsProvider).setBool(key, true);
  }
}
