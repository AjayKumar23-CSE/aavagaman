import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_config.dart';

enum MapMarkerKind { car, pickup, drop }

/// A marker the screens want on the map, independent of the maps SDK.
class MapMarkerSpec {
  const MapMarkerSpec({
    required this.id,
    required this.point,
    required this.kind,
    this.heading = 0,
  });

  final String id;
  final GeoPoint point;
  final MapMarkerKind kind;

  /// Degrees clockwise from north (cars only).
  final double heading;
}

/// A line on the map (driver track, car → drop guide).
class MapPolylineSpec {
  const MapPolylineSpec({required this.id, required this.points, this.dashed = false});

  final String id;
  final List<GeoPoint> points;

  /// Dashed: a straight guide line (no road geometry).
  final bool dashed;
}

/// What a screen wants the map to show. Screens build this; the
/// [MapBuilder] from [mapBuilderProvider] renders it (Google Maps in the app,
/// a placeholder in tests).
class RideMapSpec {
  const RideMapSpec({
    required this.center,
    this.zoom = MapConfig.defaultZoom,
    this.markers = const [],
    this.polylines = const [],
    this.fitPoints = const [],
    this.myLocation = false,
    this.interactive = true,
    this.onCameraIdle,
    this.padding = EdgeInsets.zero,
    this.recenter = 0,
  });

  final GeoPoint center;
  final double zoom;
  final List<MapMarkerSpec> markers;
  final List<MapPolylineSpec> polylines;

  /// When non-empty the camera fits these points (plus [padding]) whenever
  /// they change, instead of using [center] / [zoom].
  final List<GeoPoint> fitPoints;
  final bool myLocation;
  final bool interactive;

  /// Reports the map centre after the user stops moving it.
  final void Function(GeoPoint center)? onCameraIdle;
  final EdgeInsets padding;

  /// Bump to move a draggable map back to [center] (GPS fix arrived, locate
  /// button); draggable maps otherwise ignore [center] changes so they don't
  /// snap back under the user's finger.
  final int recenter;
}

typedef MapBuilder = Widget Function(BuildContext context, RideMapSpec spec);

/// Google Maps by default; tests override with a placeholder.
final mapBuilderProvider = Provider<MapBuilder>((ref) => (context, spec) => GoogleRideMap(spec: spec));

/// `google_maps_flutter` rendering of a [RideMapSpec].
class GoogleRideMap extends StatefulWidget {
  const GoogleRideMap({super.key, required this.spec});

  final RideMapSpec spec;

  @override
  State<GoogleRideMap> createState() => _GoogleRideMapState();
}

class _GoogleRideMapState extends State<GoogleRideMap> {
  static BitmapDescriptor? _carIcon;
  static Future<BitmapDescriptor>? _carIconLoading;

  GoogleMapController? _controller;
  List<GeoPoint> _fitted = const [];

  static LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

  @override
  void initState() {
    super.initState();
    _loadCarIcon();
  }

  Future<void> _loadCarIcon() async {
    if (_carIcon != null) return;
    _carIconLoading ??= BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(MapConfig.carMarkerSize, MapConfig.carMarkerSize)),
      MapConfig.carMarkerAsset,
      package: MapConfig.carMarkerPackage,
    );
    try {
      _carIcon = await _carIconLoading;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Car marker asset unavailable ($e)');
    }
  }

  @override
  void didUpdateWidget(covariant GoogleRideMap old) {
    super.didUpdateWidget(old);
    final spec = widget.spec;
    if (spec.fitPoints.isNotEmpty) {
      _fit(spec);
    } else if (spec.recenter != old.spec.recenter ||
        (old.spec.center != spec.center && spec.onCameraIdle == null)) {
      // Programmatic recentre: GPS fix arrived, locate button, or a new
      // centre on a non-draggable map.
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(_ll(spec.center), spec.zoom));
    }
  }

  void _fit(RideMapSpec spec) {
    final pts = spec.fitPoints;
    if (_controller == null || _samePoints(pts, _fitted)) return;
    _fitted = List.of(pts);
    if (pts.length == 1) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(_ll(pts.single), spec.zoom));
      return;
    }
    var south = pts.first.lat, north = pts.first.lat, west = pts.first.lng, east = pts.first.lng;
    for (final p in pts) {
      if (p.lat < south) south = p.lat;
      if (p.lat > north) north = p.lat;
      if (p.lng < west) west = p.lng;
      if (p.lng > east) east = p.lng;
    }
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)),
      72,
    ));
  }

  static bool _samePoints(List<GeoPoint> a, List<GeoPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Set<Marker> _markers() => {
        for (final m in widget.spec.markers)
          Marker(
            markerId: MarkerId(m.id),
            position: _ll(m.point),
            icon: switch (m.kind) {
              MapMarkerKind.car => _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              MapMarkerKind.pickup => BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              MapMarkerKind.drop => BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            },
            rotation: m.kind == MapMarkerKind.car ? m.heading : 0,
            flat: m.kind == MapMarkerKind.car,
            anchor: m.kind == MapMarkerKind.car ? const Offset(0.5, 0.5) : const Offset(0.5, 1),
            consumeTapEvents: true,
          ),
      };

  Set<Polyline> _polylines(ColorScheme scheme) => {
        for (final p in widget.spec.polylines)
          if (p.points.length >= 2)
            Polyline(
              polylineId: PolylineId(p.id),
              points: [for (final pt in p.points) _ll(pt)],
              color: p.dashed ? scheme.outline : scheme.primary,
              width: p.dashed ? 3 : 5,
              patterns: p.dashed ? [PatternItem.dash(18), PatternItem.gap(10)] : const [],
              geodesic: true,
            ),
      };

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final interactive = spec.interactive;
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _ll(spec.center), zoom: spec.zoom),
      onMapCreated: (c) {
        _controller = c;
        if (spec.fitPoints.isNotEmpty) _fit(spec);
      },
      markers: _markers(),
      polylines: _polylines(Theme.of(context).colorScheme),
      myLocationEnabled: spec.myLocation,
      myLocationButtonEnabled: spec.myLocation && interactive,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
      padding: spec.padding,
      onCameraIdle: spec.onCameraIdle == null
          ? null
          : () async {
              final c = _controller;
              if (c == null) return;
              final region = await c.getVisibleRegion();
              final centre = GeoPoint(
                (region.southwest.latitude + region.northeast.latitude) / 2,
                (region.southwest.longitude + region.northeast.longitude) / 2,
              );
              spec.onCameraIdle?.call(centre);
            },
    );
  }

  @override
  void dispose() {
    unawaited(Future.sync(() => _controller?.dispose()));
    super.dispose();
  }
}

/// Renders a [RideMapSpec] through the configured builder.
class RideMap extends ConsumerWidget {
  const RideMap({super.key, required this.spec});

  final RideMapSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(mapBuilderProvider)(context, spec);
}

/// Test / preview stand-in: a tinted box listing the markers.
Widget placeholderMapBuilder(BuildContext context, RideMapSpec spec) => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          'map ${spec.center.lat.toStringAsFixed(4)},${spec.center.lng.toStringAsFixed(4)} '
          '${spec.markers.map((m) => m.kind.name).join(',')}'
          '${spec.polylines.isEmpty ? '' : ' lines:${spec.polylines.map((p) => p.id).join(',')}'}',
          key: const Key('map-placeholder'),
          textAlign: TextAlign.center,
        ),
      ),
    );
