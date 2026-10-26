import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import 'location_feed.dart';

/// Messages between the UI isolate and the service isolate.
abstract final class ServiceEvents {
  /// service → UI: a GPS fix (`DriverFix` JSON).
  static const position = 'position';

  /// UI → service: update the foreground notification `{title, body}`.
  static const notification = 'notification';

  /// UI → service: still alive (every 15 s).
  static const ping = 'ping';

  /// UI → service: stop.
  static const stop = 'stop';
}

/// How long the service keeps running without hearing from the UI isolate.
/// If the app was killed, the server marks the driver offline after 15 s
/// anyway (SPEC §6); this just removes a stale "You are online" notification.
const serviceWatchdog = Duration(seconds: 90);

/// Entry point of the foreground service isolate (SPEC §12 background
/// location). It only streams GPS fixes to the UI isolate; it makes no
/// network calls and holds no tokens.
@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (service is AndroidServiceInstance) {
    try {
      await service.setAsForegroundService();
    } catch (e) {
      debugPrint('foreground service: $e');
    }
  }

  var lastPing = DateTime.now();
  StreamSubscription<Position>? positions;
  Timer? watchdog;

  Future<void> shutDown() async {
    await positions?.cancel();
    watchdog?.cancel();
    await service.stopSelf();
  }

  service.on(ServiceEvents.notification).listen((args) {
    if (service is AndroidServiceInstance && args != null) {
      service.setForegroundNotificationInfo(
        title: args['title']?.toString() ?? '',
        content: args['body']?.toString() ?? '',
      );
    }
  });
  service.on(ServiceEvents.ping).listen((_) => lastPing = DateTime.now());
  service.on(ServiceEvents.stop).listen((_) => shutDown());

  positions =
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 2),
        ),
      ).listen(
        (p) => service.invoke(ServiceEvents.position, positionToFix(p).toJson()),
        onError: (Object e) => debugPrint('position stream: $e'),
      );

  watchdog = Timer.periodic(const Duration(seconds: 30), (_) {
    if (DateTime.now().difference(lastPing) > serviceWatchdog) shutDown();
  });
}
