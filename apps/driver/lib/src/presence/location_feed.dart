import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ride_shared/ride_shared.dart';

import 'background_entry.dart';

/// GPS fixes while the driver is online. The real feed runs `geolocator`
/// inside the `flutter_background_service` foreground service (SPEC §12) and
/// forwards fixes to the UI isolate, which owns the socket and every REST
/// call (so token refresh has a single owner). Tests use a fake.
abstract class LocationFeed {
  /// Fixes from the running service.
  Stream<DriverFix> get fixes;

  /// One-shot fix for `POST /driver/online`; null when unavailable.
  Future<DriverFix?> currentFix();

  /// Starts the foreground service with the persistent notification.
  Future<void> start({required String notificationTitle, required String notificationBody});

  Future<void> stop();

  /// True when the service survived (e.g. the UI was recreated).
  Future<bool> isRunning();
}

class BackgroundLocationFeed implements LocationFeed {
  BackgroundLocationFeed({FlutterBackgroundService? service}) : _service = service ?? FlutterBackgroundService();

  /// Notification channel the foreground notification uses (created at
  /// startup by `setupNotifications`).
  static const channelId = 'presence';
  static const notificationId = 7001;
  static const keepAlive = Duration(seconds: 15);

  final FlutterBackgroundService _service;
  Timer? _ping;

  /// Must run once in `main()` before the service is started.
  static Future<void> configure({required String notificationTitle, required String notificationBody}) async {
    try {
      await FlutterBackgroundService().configure(
        iosConfiguration: IosConfiguration(autoStart: false),
        androidConfiguration: AndroidConfiguration(
          onStart: onServiceStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: channelId,
          initialNotificationTitle: notificationTitle,
          initialNotificationContent: notificationBody,
          foregroundServiceNotificationId: notificationId,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
      );
    } catch (e) {
      debugPrint('Background service unavailable: $e');
    }
  }

  @override
  Stream<DriverFix> get fixes => _service
      .on(ServiceEvents.position)
      .map((m) {
        final json = asMap(m) ?? const <String, dynamic>{};
        return DriverFix.fromJson(json);
      })
      .handleError((Object e) => debugPrint('position event: $e'));

  @override
  Future<DriverFix?> currentFix() async {
    // GPS first; indoors it may not warm up in time, so fall back to the
    // coarse network fix and then to the last cached position.
    final p = await _firstFix(LocationAccuracy.high, const Duration(seconds: 10)) ??
        await _firstFix(LocationAccuracy.medium, const Duration(seconds: 6));
    if (p != null) return positionToFix(p);
    try {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : positionToFix(last);
    } catch (_) {
      return null;
    }
  }

  /// First position within [limit], else null; cancelling the subscription
  /// stops the native request (a timed-out `getCurrentPosition` does not).
  static Future<Position?> _firstFix(LocationAccuracy accuracy, Duration limit) async {
    final done = Completer<Position?>();
    final sub = Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: accuracy)).listen(
      (p) {
        if (!done.isCompleted) done.complete(p);
      },
      onError: (Object e) {
        debugPrint('current fix: $e');
        if (!done.isCompleted) done.complete(null);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
    );
    final timer = Timer(limit, () {
      if (!done.isCompleted) done.complete(null);
    });
    try {
      return await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  @override
  Future<void> start({required String notificationTitle, required String notificationBody}) async {
    if (!await _service.isRunning()) await _service.startService();
    _service.invoke(ServiceEvents.notification, {'title': notificationTitle, 'body': notificationBody});
    _ping?.cancel();
    _ping = Timer.periodic(keepAlive, (_) => _service.invoke(ServiceEvents.ping));
    _service.invoke(ServiceEvents.ping);
  }

  @override
  Future<void> stop() async {
    _ping?.cancel();
    _ping = null;
    if (await _service.isRunning()) _service.invoke(ServiceEvents.stop);
  }

  @override
  Future<bool> isRunning() => _service.isRunning();
}

/// `Position` → wire fix; negative values mean "unknown" on Android.
DriverFix positionToFix(Position p) => DriverFix(
  lat: p.latitude,
  lng: p.longitude,
  heading: p.heading >= 0 ? p.heading : null,
  speed: p.speed >= 0 ? p.speed : null,
  accuracy: p.accuracy >= 0 ? p.accuracy : null,
  ts: p.timestamp.millisecondsSinceEpoch,
);
