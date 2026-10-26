// Renders the main screens to PNG files for a visual check. Skipped unless
// RIDE_SHOTS points at an output directory:
//   RIDE_SHOTS=/tmp/shots flutter test --update-goldens test/screenshots
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/providers.dart';

import '../helpers.dart';

final out = Platform.environment['RIDE_SHOTS'];

List<dynamic> fixtureList(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync()) as List<dynamic>;

Future<void> loadFonts() async {
  final jakarta = FontLoader('packages/ride_shared/PlusJakartaSans');
  for (final w in [400, 500, 600, 700, 800]) {
    jakarta.addFont(File('../shared/fonts/PlusJakartaSans-$w.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await jakarta.load();
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons');
  icons.addFont(File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.sublistView(b)));
  await icons.load();
}

/// A stylised map: streets on a pale background plus the spec's markers.
Widget fakeMap(BuildContext context, RideMapSpec spec) => CustomPaint(
      painter: _FakeMapPainter(spec, Theme.of(context).colorScheme),
      child: const SizedBox.expand(),
    );

class _FakeMapPainter extends CustomPainter {
  _FakeMapPainter(this.spec, this.scheme);

  final RideMapSpec spec;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE9EEF2));
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 4;
    for (var x = 30.0; x < size.width; x += 95) {
      canvas.drawLine(Offset(x, 0), Offset(x + 40, size.height), x % 190 == 30 ? road : minor);
    }
    for (var y = 40.0; y < size.height; y += 110) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 30), y % 220 == 40 ? road : minor);
    }
    final park = Paint()..color = const Color(0xFFCFE8D0);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.55, size.height * 0.1, 120, 90), const Radius.circular(16)), park);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.08, size.height * 0.62, 90, 70), const Radius.circular(16)), park);
    final water = Paint()..color = const Color(0xFFBFD9F2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-20, size.height * 0.35, 110, 60), const Radius.circular(30)), water);

    // Markers: spread along a diagonal, by kind.
    var i = 0;
    for (final m in spec.markers) {
      final pos = switch (m.kind) {
        MapMarkerKind.pickup => Offset(size.width * 0.32, size.height * 0.58),
        MapMarkerKind.drop => Offset(size.width * 0.72, size.height * 0.28),
        MapMarkerKind.car => Offset(size.width * (0.2 + 0.15 * (i % 4)), size.height * (0.3 + 0.12 * (i % 3))),
      };
      i++;
      _icon(canvas, pos, m.kind);
    }
    if (spec.polylines.isNotEmpty) {
      final p = Path()
        ..moveTo(size.width * 0.32, size.height * 0.58)
        ..quadraticBezierTo(size.width * 0.45, size.height * 0.25, size.width * 0.72, size.height * 0.28);
      canvas.drawPath(p, Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round);
    }
  }

  void _icon(Canvas canvas, Offset at, MapMarkerKind kind) {
    final (icon, color) = switch (kind) {
      MapMarkerKind.pickup => (Icons.circle, const Color(0xFF16A34A)),
      MapMarkerKind.drop => (Icons.location_on, const Color(0xFFE5484D)),
      MapMarkerKind.car => (Icons.local_taxi, const Color(0xFF0F172A)),
    };
    final size = kind == MapMarkerKind.pickup ? 18.0 : 34.0;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: 'MaterialIcons', fontSize: size, color: color, shadows: const [Shadow(blurRadius: 6, color: Colors.black38)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(size / 2, kind == MapMarkerKind.drop ? size : size / 2));
  }

  @override
  bool shouldRepaint(covariant _FakeMapPainter old) => old.spec != spec;
}

/// Frames without waiting to settle: countdown rings never stop animating.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$out/rider-$name.png')));
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Widget app({
  AuthTokens? tokens = saved,
  FakeRideApi? rides,
  SocketHarness? sockets,
  BookingDraft draft = const BookingDraft(),
  String? name = 'Asha',
}) =>
    testApp(
      auth: FakeAuthApi(),
      me: FakeMeApi(rider(name: name)),
      tokens: tokens,
      rides: rides,
      sockets: sockets,
      draft: draft,
      mapBuilder: fakeMap,
    );

void main() {
  setUpAll(loadFonts);

  group('screenshots', skip: out == null, () {
    testWidgets('login', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(tokens: null));
      await tester.pumpAndSettle();
      await shot(tester, '01-phone');
      await tester.enterText(find.byType(TextField), '9800000002');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await shot(tester, '02-otp');
    });

    testWidgets('home', (tester) async {
      phone(tester);
      final api = FakeRideApi()
        ..nearbyResult = [for (final d in fixtureList('drivers_nearby.json')) NearbyDriver.fromJson(d as Map<String, dynamic>)];
      await tester.pumpWidget(app(rides: api));
      await tester.pumpAndSettle();
      await shot(tester, '03-home');
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await shot(tester, '04-drawer');
    });

    testWidgets('confirm', (tester) async {
      phone(tester);
      final api = FakeRideApi()..estimateJson = fixture('fare_estimate.json');
      await tester.pumpWidget(app(rides: api, draft: const BookingDraft(pickup: cp, drop: indiaGate)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('where-to')));
      await tester.pumpAndSettle();
      await shot(tester, '05-search');
      await tester.enterText(find.byKey(const Key('search-field')), 'India Gate');
      await tester.pump();
      await tester.tap(find.byKey(const Key('set-on-map')));
      await tester.pumpAndSettle();
      await shot(tester, '06-pick-on-map');
      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();
      await shot(tester, '06b-confirm');
    });

    for (final (name, fixtureName) in [
      ('07-finding', 'ride_requested.json'),
      ('08-assigned', 'ride_accepted_rider_view.json'),
      ('09-arrived', 'ride_arrived_rider_view.json'),
      ('10-trip', 'ride_started_rider_view.json'),
      ('11-payment', 'ride_completed_rider_view.json'),
      ('12-rate', 'ride_paid_rider_view.json'),
      ('13-cancelled', 'ride_cancelled_after_arrived_fee.json'),
    ]) {
      testWidgets(name, (tester) async {
        phone(tester);
        final sockets = SocketHarness();
        final ride = rideFrom(fixtureName);
        final api = FakeRideApi()
          ..activeRide = ride
          ..receiptResult = RideReceipt.fromJson(fixture('receipt_completed_cash.json'));
        await tester.pumpWidget(app(rides: api, sockets: sockets));
        await settle(tester);
        sockets.connect();
        await settle(tester);
        if (ride.status == RideStatus.accepted || ride.status == RideStatus.arrived || ride.status == RideStatus.started) {
          sockets.emit('driver:position', fixture('ws_driver_position.json')..['ride_id'] = ride.id);
          await tester.pump(const Duration(seconds: 1));
        }
        await shot(tester, name);
      });
    }

    testWidgets('history', (tester) async {
      phone(tester);
      final api = FakeRideApi()
        ..historyRides = RidePageResult.fromJson(fixture('rides_page1.json')).data
        ..receiptResult = RideReceipt.fromJson(fixture('receipt_paid_cash.json'));
      await tester.pumpWidget(app(rides: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-history')));
      await tester.pumpAndSettle();
      await shot(tester, '14-history');
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await shot(tester, '15-detail');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Profile')));
      await tester.pumpAndSettle();
      await shot(tester, '16-profile');
    });

    testWidgets('dark mode', (tester) async {
      phone(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final sockets = SocketHarness();
      final api = FakeRideApi()..activeRide = rideFrom('ride_accepted_rider_view.json');
      await tester.pumpWidget(app(rides: api, sockets: sockets));
      await settle(tester);
      sockets.connect();
      await settle(tester);
      await shot(tester, '20-dark-assigned');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(rides: FakeRideApi()..historyRides = RidePageResult.fromJson(fixture('rides_page1.json')).data));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-history')));
      await tester.pumpAndSettle();
      await shot(tester, '21-dark-history');
    });
  });
}
