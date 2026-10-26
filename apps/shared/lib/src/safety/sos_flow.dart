import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../api/ride_api.dart';
import '../map/map_config.dart';

/// Opens a URI in an external app (the dialer). Returns false when nothing
/// could handle it.
typedef UriLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) =>
    launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

/// Result of [SosFlow.raise].
class SosResult {
  const SosResult({required this.dialled, required this.alerted, this.error});

  /// The dialer opened with the emergency number.
  final bool dialled;

  /// `POST /rides/:id/sos` succeeded (the support team is alerted).
  final bool alerted;

  /// Why the alert failed, if it did.
  final Object? error;
}

/// SOS (SPEC §11, §12): after the user confirms, open the dialer with the
/// emergency number, then post the alert with the current position — in that
/// order, so the call is never delayed by the network. Used by both apps.
class SosFlow {
  SosFlow({
    required this.api,
    UriLauncher? launch,
    this.emergencyNumber = '112',
  }) : _launch = launch ?? _defaultLauncher;

  final RideApi api;
  final UriLauncher _launch;
  final String emergencyNumber;

  Uri get dialUri => Uri(scheme: 'tel', path: emergencyNumber);

  Future<SosResult> raise({required String rideId, required GeoPoint at}) async {
    var dialled = false;
    try {
      dialled = await _launch(dialUri);
    } catch (e) {
      debugPrint('SOS dialer: $e');
    }
    try {
      await api.sos(rideId, lat: at.lat, lng: at.lng);
      return SosResult(dialled: dialled, alerted: true);
    } catch (e) {
      debugPrint('SOS alert failed: $e');
      return SosResult(dialled: dialled, alerted: false, error: e);
    }
  }
}
