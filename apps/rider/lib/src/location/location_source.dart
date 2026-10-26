import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:ride_shared/ride_shared.dart';

/// Result of asking for the phone's position.
class LocationResult {
  const LocationResult({this.point, this.denied = false, this.serviceOff = false});

  /// Null when unavailable; callers fall back to [MapConfig.connaughtPlace].
  final GeoPoint? point;

  /// Permission denied (possibly permanently) → show the prompt (SPEC §11).
  final bool denied;

  /// Location services switched off on the device.
  final bool serviceOff;

  /// Allowed and switched on, but no fix came back (indoors, no signal…).
  bool get unavailable => point == null && !denied && !serviceOff;

  GeoPoint get pointOrDefault => point ?? MapConfig.connaughtPlace;
}

/// Where the rider is. Abstract so tests can fake it.
abstract class LocationSource {
  /// Requests "while in use" permission if needed and returns a fix.
  Future<LocationResult> current();

  /// Live fixes after [current] succeeded; ends silently when they stop.
  Stream<GeoPoint> updates();

  /// Opens the app's settings page (after a permanent denial).
  Future<void> openSettings();
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  /// A cached fix younger than this is good enough to start with; [updates]
  /// refines it once GPS is warm.
  static const freshEnough = Duration(minutes: 2);

  /// GPS first (accurate, slow to warm up indoors), then network/cell (fast,
  /// coarse), then whatever the phone had cached.
  static const gpsWait = Duration(seconds: 10);
  static const coarseWait = Duration(seconds: 6);

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(serviceOff: true);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationResult(denied: true);
      }
      final last = await _lastKnown();
      if (last != null && DateTime.now().difference(last.timestamp) < freshEnough) {
        return _of(last);
      }
      final pos = await _firstFix(LocationAccuracy.high, gpsWait) ??
          await _firstFix(LocationAccuracy.medium, coarseWait) ??
          last;
      return pos == null ? const LocationResult() : _of(pos);
    } catch (_) {
      return const LocationResult();
    }
  }

  @override
  Stream<GeoPoint> updates() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).map((p) => GeoPoint(p.latitude, p.longitude)).handleError((Object _) {});

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();

  static LocationResult _of(Position p) => LocationResult(point: GeoPoint(p.latitude, p.longitude));

  static Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// First position within [limit], else null. Subscribes to the stream
  /// rather than `getCurrentPosition(timeLimit:)`, whose timeout leaves the
  /// native request running; cancelling the subscription stops it.
  static Future<Position?> _firstFix(LocationAccuracy accuracy, Duration limit) async {
    final done = Completer<Position?>();
    final sub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: accuracy),
    ).listen(
      (p) {
        if (!done.isCompleted) done.complete(p);
      },
      onError: (Object _) {
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
}

/// Fixed answer, for tests and previews.
class FixedLocationSource implements LocationSource {
  const FixedLocationSource(this.result, {this.live = const Stream.empty()});

  final LocationResult result;

  /// What [updates] emits (tests feed a controller's stream).
  final Stream<GeoPoint> live;

  @override
  Future<LocationResult> current() async => result;

  @override
  Stream<GeoPoint> updates() => live;

  @override
  Future<void> openSettings() async {}
}
