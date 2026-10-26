import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// What stands between the driver and going online (SPEC §12 permissions).
enum PermissionProblem {
  /// Location services switched off.
  serviceOff,

  /// ACCESS_FINE_LOCATION denied.
  locationDenied,

  /// ACCESS_BACKGROUND_LOCATION ("All the time") denied — Android 10+.
  backgroundDenied,

  /// POST_NOTIFICATIONS denied — the driver can still go online but will
  /// not hear requests with the screen off.
  notificationsDenied;

  bool get blocksOnline => this != notificationsDenied;
}

abstract class PermissionGate {
  /// Requests what is missing and reports what is still missing.
  Future<Set<PermissionProblem>> ensure();

  Future<void> openAppSettings();

  Future<void> openLocationSettings();
}

class AndroidPermissionGate implements PermissionGate {
  const AndroidPermissionGate();

  @override
  Future<Set<PermissionProblem>> ensure() async {
    final problems = <PermissionProblem>{};
    try {
      if (!await Geolocator.isLocationServiceEnabled()) problems.add(PermissionProblem.serviceOff);
      var fine = await Geolocator.checkPermission();
      if (fine == LocationPermission.denied) fine = await Geolocator.requestPermission();
      if (fine == LocationPermission.denied || fine == LocationPermission.deniedForever) {
        problems.add(PermissionProblem.locationDenied);
        return problems;
      }
      // Background location needs a second, separate request on Android 10+.
      if (!await Permission.locationAlways.isGranted) {
        final r = await Permission.locationAlways.request();
        if (!r.isGranted) problems.add(PermissionProblem.backgroundDenied);
      }
      if (!await Permission.notification.isGranted) {
        final r = await Permission.notification.request();
        if (!r.isGranted) problems.add(PermissionProblem.notificationsDenied);
      }
    } catch (e) {
      debugPrint('permissions: $e');
    }
    return problems;
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  @override
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }
}
