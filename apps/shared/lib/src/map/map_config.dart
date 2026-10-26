import 'dart:math';

/// A WGS-84 point. Plain Dart so the shared package stays free of the maps
/// SDK; the rider app converts to `LatLng`.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Great-circle distance in metres.
  double distanceTo(GeoPoint other) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(other.lat - lat);
    final dLng = rad(other.lng - lng);
    final a = pow(sin(dLat / 2), 2) + cos(rad(lat)) * cos(rad(other.lat)) * pow(sin(dLng / 2), 2);
    return 2 * r * asin(sqrt(a));
  }

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(GeoPoint p) =>
      p.lat >= south && p.lat <= north && p.lng >= west && p.lng <= east;

  GeoPoint get center => GeoPoint((south + north) / 2, (west + east) / 2);
}

/// Map defaults shared by both apps (SPEC §11, Appendix A).
abstract final class MapConfig {
  /// Places restriction and OSRM clip: SW (28.20, 76.80), NE (28.95, 77.70).
  static const ncrBounds = GeoBounds(south: 28.20, west: 76.80, north: 28.95, east: 77.70);

  /// Where the map centres when location permission is denied.
  static const connaughtPlace = GeoPoint(28.6315, 77.2167);

  static const defaultZoom = 15.0;

  /// Top-down car icon, 128×128, drawn facing north; rotate by heading.
  static const carMarkerAsset = 'assets/car_marker.png';
  static const carMarkerPackage = 'ride_shared';

  /// Logical size the car icon is rendered at on the map.
  static const carMarkerSize = 40.0;

  /// Nearby cars refresh interval (SPEC §11).
  static const nearbyRefresh = Duration(seconds: 10);
}

/// Distance for display: "850 m" / "3.1 km".
String formatDistance(int metres) =>
    metres < 1000 ? '$metres m' : '${(metres / 1000).toStringAsFixed(1)} km';

/// Duration for display: "1 min" / "12 min".
String formatMinutes(int seconds) => '${max(1, (seconds / 60).round())} min';

/// "₹82 – ₹95" (whole rupees).
String formatFareRange(double min, double max) => '₹${min.round()} – ₹${max.round()}';

/// "₹215".
String formatFare(double amount) => '₹${amount.round()}';

/// Money with paise only when needed: "₹118", "₹4.19", "-₹12.57".
String formatAmount(double amount) {
  final sign = amount < 0 ? '-' : '';
  final a = amount.abs();
  final whole = (a - a.roundToDouble()).abs() < 0.005;
  return '$sign₹${whole ? a.round().toString() : a.toStringAsFixed(2)}';
}

/// "0:12" / "12:05" / "1:02:03" for trip durations.
String formatClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
}
