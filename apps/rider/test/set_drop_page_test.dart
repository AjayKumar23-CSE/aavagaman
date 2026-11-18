import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/location/location_source.dart';
import 'package:rider/src/providers.dart';

import 'helpers.dart';

/// Places search over a fixed list (address → coordinates).
class FakePlaces implements PlacesApi {
  const FakePlaces();

  static const places = {
    'saket': PlaceDetails(lat: 28.5245, lng: 77.2066, address: 'Saket, New Delhi'),
    'india-gate': PlaceDetails(lat: 28.6129, lng: 77.2295, address: 'India Gate, New Delhi'),
  };

  @override
  bool get isAvailable => true;

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken}) async => [
        for (final e in places.entries)
          if (e.value.address.toLowerCase().contains(input.toLowerCase()))
            PlaceSuggestion(placeId: e.key, primaryText: e.value.address.split(',').first, secondaryText: 'New Delhi'),
      ];

  @override
  Future<PlaceDetails> details(String placeId, {required String sessionToken}) async => places[placeId]!;
}

BookingDraft draftOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).last)).read(bookingDraftProvider);

TextField field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key)));

Future<void> openSearch(
  WidgetTester tester, {
  LocationResult location = const LocationResult(point: GeoPoint(28.6315, 77.2167)),
  Stream<GeoPoint> locationUpdates = const Stream.empty(),
  PlacesApi places = const NoPlacesApi(),
}) async {
  tallScreen(tester);
  final rides = FakeRideApi()..estimateJson = fixture('fare_estimate.json');
  await tester.pumpWidget(testApp(
    auth: FakeAuthApi(),
    me: FakeMeApi(rider(name: 'Asha')),
    tokens: saved,
    rides: rides,
    location: location,
    locationUpdates: locationUpdates,
    places: places,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('where-to')));
  await tester.pumpAndSettle();
  expect(find.text('Plan your ride'), findsOneWidget);
}

Future<void> searchAndPick(WidgetTester tester, String key, String query, String result) async {
  await tester.enterText(find.byKey(Key(key)), query);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, result));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Where to: pickup is the current location, follows the GPS, drop has the focus', (tester) async {
    final live = StreamController<GeoPoint>();
    await openSearch(tester, locationUpdates: live.stream);

    expect(field(tester, 'pickup-field').controller!.text, 'Current location');
    expect(field(tester, 'search-field').focusNode!.hasFocus, isTrue);
    expect(draftOf(tester).pickup?.lat, 28.6315);

    live.add(const GeoPoint(28.5001, 77.25));
    await tester.pumpAndSettle();
    expect(draftOf(tester).pickup?.lat, 28.5001);
    expect(draftOf(tester).pickup?.address, 'Current location');
    await live.close();
  });

  testWidgets('a searched pickup replaces the current location and stops following the GPS', (tester) async {
    final live = StreamController<GeoPoint>();
    await openSearch(tester, locationUpdates: live.stream, places: const FakePlaces());

    await searchAndPick(tester, 'pickup-field', 'Saket', 'Saket');
    expect(draftOf(tester).pickup?.address, 'Saket, New Delhi');
    expect(field(tester, 'pickup-field').controller!.text, 'Saket, New Delhi');
    expect(field(tester, 'search-field').focusNode!.hasFocus, isTrue, reason: 'on to the drop');

    live.add(const GeoPoint(28.5001, 77.25));
    await tester.pumpAndSettle();
    expect(draftOf(tester).pickup?.address, 'Saket, New Delhi');

    await searchAndPick(tester, 'search-field', 'India', 'India Gate');
    expect(find.text('Confirm your ride'), findsOneWidget);
    expect(find.text('Saket, New Delhi'), findsOneWidget);
    expect(find.text('India Gate, New Delhi'), findsOneWidget);
    await live.close();
  });

  testWidgets('"Use current location" puts the GPS pickup back', (tester) async {
    await openSearch(tester, places: const FakePlaces());
    await searchAndPick(tester, 'pickup-field', 'Saket', 'Saket');
    expect(draftOf(tester).pickup?.address, 'Saket, New Delhi');

    await tester.tap(find.byKey(const Key('pickup-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('use-current-location')));
    await tester.pumpAndSettle();
    expect(draftOf(tester).pickup?.address, 'Current location');
    expect(draftOf(tester).pickup?.lat, 28.6315);
    expect(field(tester, 'pickup-field').controller!.text, 'Current location');
  });

  testWidgets('no GPS fix: no Connaught Place pickup; the drop waits until a pickup is set', (tester) async {
    await openSearch(tester, location: const LocationResult(denied: true));

    expect(draftOf(tester).pickup, isNull);
    expect(field(tester, 'pickup-field').controller!.text, isEmpty);
    expect(find.text('Enter pickup location'), findsOneWidget);
    expect(find.byKey(const Key('use-current-location')), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'India Gate');
    await tester.pump();
    await tester.tap(find.byKey(const Key('set-on-map')));
    await tester.pumpAndSettle();
    expect(find.text('Set your pickup location first.'), findsOneWidget);
    expect(field(tester, 'pickup-field').focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byKey(const Key('pickup-field')), 'Saket metro gate 2');
    await tester.pump();
    await tester.tap(find.byKey(const Key('set-on-map')));
    await tester.pumpAndSettle();
    expect(find.text('Set pickup on map'), findsOneWidget);
    await tester.tap(find.text('Confirm location'));
    await tester.pumpAndSettle();
    expect(draftOf(tester).pickup?.address, 'Saket metro gate 2');
    expect(field(tester, 'pickup-field').controller!.text, 'Saket metro gate 2');

    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('set-on-map')));
    await tester.pumpAndSettle();
    expect(find.text('Set drop on map'), findsOneWidget);
    await tester.tap(find.text('Confirm location'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your ride'), findsOneWidget);
    expect(find.text('Saket metro gate 2'), findsOneWidget);
    expect(find.text('India Gate'), findsOneWidget);
  });
}
