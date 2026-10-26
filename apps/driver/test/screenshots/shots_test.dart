// Renders the driver app's main screens to PNG files for a visual check.
// Skipped unless RIDE_SHOTS points at an output directory:
//   RIDE_SHOTS=/tmp/shots flutter test --update-goldens test/screenshots
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import '../helpers.dart';

final out = Platform.environment['RIDE_SHOTS'];

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

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$out/driver-$name.png')));
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> openDrawerItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  group('screenshots', skip: out == null, () {
    testWidgets('login + registration', (tester) async {
      phone(tester);
      final auth = FakeAuthApi(driverUser(null));
      await tester.pumpWidget(testApp(driver: FakeDriverApi(newDriverProfile()), tokens: null, auth: auth, user: driverUser(null)));
      await tester.pumpAndSettle();
      await shot(tester, '01-phone');
      await tester.enterText(find.byType(TextField), '9800000001');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('otp-field')), '123456');
      await tester.pumpAndSettle();
      await shot(tester, '02-registration');
    });

    testWidgets('documents', (tester) async {
      phone(tester);
      await tester.pumpWidget(testApp(driver: FakeDriverApi(profileFrom('driver_me_pending.json', (j) {
        j['documents'] = <Object>[];
        j['missing_documents'] = [for (final t in DocType.mandatoryTypes) t.wire];
      }))));
      await tester.pumpAndSettle();
      await shot(tester, '03-documents');
    });

    testWidgets('pending', (tester) async {
      phone(tester);
      await tester.pumpWidget(testApp(driver: FakeDriverApi(profileFrom('driver_me_rejected_doc.json'))));
      await tester.pumpAndSettle();
      await shot(tester, '04-pending');
    });

    testWidgets('home, drawer, earnings, history, profile, battery', (tester) async {
      phone(tester);
      final rides = FakeRideApi()
        ..earnings[EarningsPeriod.today] = DriverEarnings.fromJson(fixture('driver_earnings_today.json'))
        ..earnings[EarningsPeriod.week] = DriverEarnings.fromJson(fixture('driver_earnings_week.json'))
        ..historyRides = RidePageResult.fromJson(fixture('driver_rides_page1.json')).data;
      await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile()), rides: rides));
      await tester.pumpAndSettle();
      await shot(tester, '05-home-offline');
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await shot(tester, '06-drawer');
      await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Earnings')));
      await tester.pumpAndSettle();
      await shot(tester, '07-earnings');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openDrawerItem(tester, 'Trip history');
      await shot(tester, '08-history');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openDrawerItem(tester, 'Profile, vehicle & documents');
      await shot(tester, '17-profile');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openDrawerItem(tester, 'Battery settings');
      await shot(tester, '18-battery');
    });

    testWidgets('online + offer', (tester) async {
      phone(tester);
      final sockets = SocketHarness();
      await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile()), sockets: sockets));
      await tester.pumpAndSettle();
      sockets.connect();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('online-switch')));
      await tester.pumpAndSettle();
      await shot(tester, '09-home-online');
      sockets.emit('ride:offer', fixture('ws_ride_offer.json')..['expires_at'] = DateTime.now().toUtc().add(const Duration(seconds: 17)).toIso8601String());
      sockets.emit('ride:offer', {
        'ride_id': 'second-request',
        'pickup': {'lat': 28.6, 'lng': 77.227, 'address': 'Khan Market, New Delhi'},
        'drop_address': 'Select Citywalk, Saket',
        'distance_to_pickup_m': 2300,
        'est_fare_min': 162,
        'est_fare_max': 187,
        'expires_at': DateTime.now().toUtc().add(const Duration(seconds: 12)).toIso8601String(),
      });
      await settle(tester);
      await shot(tester, '10-offer');
      await tester.pumpWidget(const SizedBox());
    });

    for (final (name, fixtureName) in [
      ('11-trip-accepted', 'ride_accepted_driver_view.json'),
      ('12-trip-arrived', 'ride_arrived_driver_view.json'),
      ('13-trip-started', 'ride_started_driver_view.json'),
      ('14-collect-cash', 'ride_completed_driver_view.json'),
      ('15-rate', 'ride_paid_driver_view.json'),
    ]) {
      testWidgets(name, (tester) async {
        phone(tester);
        final rides = FakeRideApi()..activeRide = rideFrom(fixtureName);
        await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile()), rides: rides));
        await settle(tester);
        await shot(tester, name);
      });
    }

    testWidgets('suspended', (tester) async {
      phone(tester);
      await tester.pumpWidget(testApp(driver: FakeDriverApi(profileFrom('driver_me_pending.json', (j) {
        j['verification_status'] = 'suspended';
        j['reviewer_note'] = 'Three cancellations today. Call support to reinstate.';
      }))));
      await tester.pumpAndSettle();
      await shot(tester, '16-suspended');
    });
  });
}
