import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/location/location_source.dart';
import 'package:rider/src/providers.dart';

import 'helpers.dart';

const saved = AuthTokens(accessToken: 'a1', refreshToken: 'r1');

void main() {
  testWidgets('saved session: Splash restores via GET /me and shows Home with the greeting',
      (tester) async {
    await tester.pumpWidget(testApp(auth: FakeAuthApi(), me: FakeMeApi(rider(name: 'Asha')), tokens: saved));
    await tester.pumpAndSettle();

    expect(find.text('Hi Asha'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
  });

  testWidgets('home: the map follows live location updates and "Where to?" picks up the latest fix',
      (tester) async {
    final live = StreamController<GeoPoint>();
    await tester.pumpWidget(testApp(
      auth: FakeAuthApi(),
      me: FakeMeApi(rider(name: 'Asha')),
      tokens: saved,
      location: const LocationResult(point: GeoPoint(28.4965, 77.2426)),
      locationUpdates: live.stream,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('map 28.4965,77.2426'), findsOneWidget);
    expect(find.byKey(const Key('location-unavailable')), findsNothing);

    live.add(const GeoPoint(28.5001, 77.2500));
    await tester.pumpAndSettle();
    expect(find.textContaining('map 28.5001,77.2500'), findsOneWidget);

    await tester.tap(find.byKey(const Key('where-to')));
    await tester.pumpAndSettle();
    final draft = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)).read(bookingDraftProvider);
    expect(draft.pickup?.lat, 28.5001);
    expect(draft.pickup?.lng, 77.25);
    await live.close();
  });

  testWidgets('home: no fix (allowed but nothing came back) shows the fallback notice with Retry',
      (tester) async {
    await tester.pumpWidget(testApp(
      auth: FakeAuthApi(),
      me: FakeMeApi(rider(name: 'Asha')),
      tokens: saved,
      location: const LocationResult(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('map 28.6315,77.2167'), findsOneWidget);
    expect(find.byKey(const Key('location-unavailable')), findsOneWidget);
    expect(find.textContaining('Connaught Place'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('no saved session: Splash goes to Phone', (tester) async {
    await tester.pumpWidget(testApp(auth: FakeAuthApi(), me: FakeMeApi(rider())));
    await tester.pumpAndSettle();

    expect(find.text('Enter your mobile number'), findsOneWidget);
  });

  testWidgets('drawer: delete account confirms, calls DELETE /me and returns to Phone',
      (tester) async {
    final me = FakeMeApi(rider(name: 'Asha'));
    await tester.pumpWidget(testApp(auth: FakeAuthApi(), me: me, tokens: saved));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(me.deleted, isTrue);
    expect(find.text('Enter your mobile number'), findsOneWidget);
  });

  testWidgets('drawer: delete account during a ride shows the server message', (tester) async {
    final me = FakeMeApi(rider(name: 'Asha'))
      ..deleteError = const ApiException(
          code: 'ACTIVE_RIDE', message: 'Finish or cancel your ride first', statusCode: 409);
    await tester.pumpWidget(testApp(auth: FakeAuthApi(), me: me, tokens: saved));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Finish or cancel your ride first'), findsOneWidget);
    expect(find.text('Hi Asha'), findsOneWidget);
  });

  testWidgets('profile: edits name and email via PATCH /me', (tester) async {
    final me = FakeMeApi(rider(name: 'Asha'));
    await tester.pumpWidget(testApp(auth: FakeAuthApi(), me: me, tokens: saved));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Asha Verma');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email (optional)'), 'not-an-email');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(me.updates, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email (optional)'), 'asha@example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(me.updates.single, (name: 'Asha Verma', email: 'asha@example.com'));
    expect(find.text('Profile updated'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Hi Asha Verma'), findsOneWidget);
  });
}
