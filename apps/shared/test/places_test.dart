import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

const autocompleteJson = {
  'suggestions': [
    {
      'placePrediction': {
        'place': 'places/ChIJC03rqdriDDkRXT6SJRGXFwc',
        'placeId': 'ChIJC03rqdriDDkRXT6SJRGXFwc',
        'text': {'text': 'India Gate, Rajpath, India Gate, New Delhi, Delhi, India'},
        'structuredFormat': {
          'mainText': {'text': 'India Gate'},
          'secondaryText': {'text': 'Rajpath, India Gate, New Delhi, Delhi, India'},
        },
      },
    },
    {
      'queryPrediction': {'text': {'text': 'india gate restaurants'}},
    },
    {
      'placePrediction': {
        'place': 'places/abc',
        'text': {'text': 'Somewhere'},
      },
    },
  ],
};

const detailsJson = {
  'name': 'places/ChIJC03rqdriDDkRXT6SJRGXFwc',
  'formattedAddress': 'Kartavya Path, India Gate, New Delhi, Delhi 110001, India',
  'location': {'latitude': 28.612912, 'longitude': 77.2295097},
  'displayName': {'text': 'India Gate', 'languageCode': 'en'},
};

void main() {
  test('parses autocomplete suggestions, skipping query predictions', () {
    final list = GooglePlacesApi.parseAutocomplete(autocompleteJson);
    expect(list, hasLength(2));
    expect(list.first.placeId, 'ChIJC03rqdriDDkRXT6SJRGXFwc');
    expect(list.first.primaryText, 'India Gate');
    expect(list.first.secondaryText, startsWith('Rajpath'));
    expect(list.first.fullText, 'India Gate, Rajpath, India Gate, New Delhi, Delhi, India');
    // Falls back to `place` and the plain text when structuredFormat is absent.
    expect(list.last.placeId, 'abc');
    expect(list.last.primaryText, 'Somewhere');
    expect(list.last.fullText, 'Somewhere');
  });

  test('parses place details into coordinates and a display address', () {
    final d = GooglePlacesApi.parseDetails(detailsJson);
    expect(d.lat, 28.612912);
    expect(d.lng, 77.2295097);
    expect(d.address, 'India Gate, Kartavya Path, India Gate, New Delhi, Delhi 110001, India');
    expect(() => GooglePlacesApi.parseDetails({'formattedAddress': 'x'}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PLACE_NO_LOCATION')));
  });

  test('autocomplete request: key header, NCR rectangle, India only, session token', () async {
    final adapter = FakeAdapter((_) => (status: 200, body: autocompleteJson));
    final api = GooglePlacesApi(apiKey: 'KEY', adapter: adapter);
    expect(api.isAvailable, isTrue);

    final res = await api.autocomplete('india ga', sessionToken: 'sess-1');
    expect(res, hasLength(2));
    final call = adapter.calls.single;
    expect(call.uri.toString(), 'https://places.googleapis.com/v1/places:autocomplete');
    expect(call.headers['X-Goog-Api-Key'], 'KEY');
    expect(adapter.jsonBody(0), {
      'input': 'india ga',
      'sessionToken': 'sess-1',
      'includedRegionCodes': ['in'],
      'locationRestriction': {
        'rectangle': {
          'low': {'latitude': 28.20, 'longitude': 76.80},
          'high': {'latitude': 28.95, 'longitude': 77.70},
        },
      },
    });
  });

  test('details request reuses the session token and asks for the field mask', () async {
    final adapter = FakeAdapter((_) => (status: 200, body: detailsJson));
    final d = await GooglePlacesApi(apiKey: 'KEY', adapter: adapter)
        .details('ChIJC03rqdriDDkRXT6SJRGXFwc', sessionToken: 'sess-1');
    expect(d.lat, 28.612912);
    final call = adapter.calls.single;
    expect(call.uri.path, '/v1/places/ChIJC03rqdriDDkRXT6SJRGXFwc');
    expect(call.uri.queryParameters, {'sessionToken': 'sess-1'});
    expect(call.headers['X-Goog-FieldMask'], 'location,formattedAddress,displayName');
  });

  test('Google error bodies become ApiException with the status name', () async {
    final adapter = FakeAdapter((_) => (
          status: 403,
          body: {
            'error': {'code': 403, 'message': 'The provided API key is invalid.', 'status': 'PERMISSION_DENIED'}
          },
        ));
    await expectLater(
      GooglePlacesApi(apiKey: 'bad', adapter: adapter).autocomplete('abc', sessionToken: 's'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'PERMISSION_DENIED')
          .having((e) => e.message, 'message', contains('API key'))),
    );
  });

  test('NoPlacesApi is unavailable and returns nothing', () async {
    const api = NoPlacesApi();
    expect(api.isAvailable, isFalse);
    expect(await api.autocomplete('abc', sessionToken: 's'), isEmpty);
    expect(() => api.details('x', sessionToken: 's'), throwsStateError);
  });

  test('session tokens look like UUID v4 and differ', () {
    final a = newPlacesSessionToken();
    final b = newPlacesSessionToken();
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(a, isNot(b));
  });

  test('placesApiProvider picks Google only with a key', () {
    final withKey = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'x', googleMapsApiKey: 'k')),
    ]);
    final without = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'x')),
    ]);
    addTearDown(withKey.dispose);
    addTearDown(without.dispose);
    expect(withKey.read(placesApiProvider), isA<GooglePlacesApi>());
    expect(without.read(placesApiProvider), isA<NoPlacesApi>());
    expect(without.read(placesApiProvider).isAvailable, isFalse);
  });
}
