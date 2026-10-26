import 'dart:math';

import 'package:dio/dio.dart';

import '../api/api_exception.dart';
import '../map/map_config.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    this.secondaryText = '',
  });

  final String placeId;

  /// "India Gate".
  final String primaryText;

  /// "Rajpath, New Delhi, Delhi".
  final String secondaryText;

  String get fullText => secondaryText.isEmpty ? primaryText : '$primaryText, $secondaryText';
}

class PlaceDetails {
  const PlaceDetails({required this.lat, required this.lng, required this.address});

  final double lat;
  final double lng;
  final String address;
}

/// Places search for the drop / pickup screen (SPEC §11).
abstract class PlacesApi {
  /// False when no API key is configured: the search screen then offers a
  /// typed address plus "Set location on map" only.
  bool get isAvailable;

  /// Predictions for [input] (callers debounce 400 ms and require ≥ 3 chars).
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken});

  /// Coordinates + formatted address. Pass the same [sessionToken] as the
  /// autocomplete calls to close the billing session.
  Future<PlaceDetails> details(String placeId, {required String sessionToken});
}

/// Used when `GOOGLE_MAPS_API_KEY` is empty and in tests.
class NoPlacesApi implements PlacesApi {
  const NoPlacesApi();

  @override
  bool get isAvailable => false;

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken}) async =>
      const [];

  @override
  Future<PlaceDetails> details(String placeId, {required String sessionToken}) =>
      throw StateError('Places search is not configured');
}

/// Google Places API (New): `places:autocomplete` restricted to the NCR
/// rectangle and India, then `GET places/{id}` for location + address.
class GooglePlacesApi implements PlacesApi {
  GooglePlacesApi({
    required this.apiKey,
    this.bounds = MapConfig.ncrBounds,
    HttpClientAdapter? adapter,
    String baseUrl = 'https://places.googleapis.com/v1',
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {'X-Goog-Api-Key': apiKey},
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
        )) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final String apiKey;
  final GeoBounds bounds;
  final Dio _dio;

  @override
  bool get isAvailable => apiKey.isNotEmpty;

  @override
  Future<List<PlaceSuggestion>> autocomplete(String input, {required String sessionToken}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/places:autocomplete', data: {
          'input': input,
          'sessionToken': sessionToken,
          'includedRegionCodes': ['in'],
          'locationRestriction': {
            'rectangle': {
              'low': {'latitude': bounds.south, 'longitude': bounds.west},
              'high': {'latitude': bounds.north, 'longitude': bounds.east},
            },
          },
        });
        return parseAutocomplete(res.data ?? const {});
      });

  @override
  Future<PlaceDetails> details(String placeId, {required String sessionToken}) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/places/$placeId',
          queryParameters: {'sessionToken': sessionToken},
          options: Options(headers: {'X-Goog-FieldMask': 'location,formattedAddress,displayName'}),
        );
        return parseDetails(res.data ?? const {});
      });

  /// `{suggestions:[{placePrediction:{placeId, structuredFormat:{mainText:{text}, secondaryText:{text}}, text:{text}}}]}`
  static List<PlaceSuggestion> parseAutocomplete(Map<String, dynamic> json) => [
        for (final s in (json['suggestions'] as List? ?? const []))
          if (s is Map && s['placePrediction'] is Map) _suggestion((s['placePrediction'] as Map).cast()),
      ];

  static PlaceSuggestion _suggestion(Map<String, dynamic> p) {
    final fmt = (p['structuredFormat'] as Map?)?.cast<String, dynamic>();
    final main = _text(fmt?['mainText']) ?? _text(p['text']) ?? '';
    final secondary = _text(fmt?['secondaryText']) ?? '';
    return PlaceSuggestion(
      placeId: p['placeId'] as String? ?? (p['place'] as String? ?? '').replaceFirst('places/', ''),
      primaryText: main,
      secondaryText: secondary,
    );
  }

  /// `{location:{latitude,longitude}, formattedAddress, displayName:{text}}`
  static PlaceDetails parseDetails(Map<String, dynamic> json) {
    final loc = (json['location'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lat = (loc['latitude'] as num?)?.toDouble();
    final lng = (loc['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      throw const ApiException(code: 'PLACE_NO_LOCATION', message: 'This place has no location');
    }
    final name = _text(json['displayName']);
    final formatted = json['formattedAddress'] as String? ?? '';
    final address = name == null || name.isEmpty || formatted.startsWith(name)
        ? formatted
        : (formatted.isEmpty ? name : '$name, $formatted');
    return PlaceDetails(lat: lat, lng: lng, address: address);
  }

  static String? _text(Object? v) => v is Map ? v['text'] as String? : null;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final data = e.response?.data;
      final err = data is Map && data['error'] is Map ? data['error'] as Map : null;
      if (err != null) {
        throw ApiException(
          code: err['status']?.toString() ?? 'PLACES_ERROR',
          message: err['message']?.toString() ?? 'Places search failed',
          statusCode: e.response?.statusCode,
        );
      }
      throw ApiException.fromDio(e);
    }
  }
}

/// Random UUID-shaped token; one per search session (SPEC §11).
String newPlacesSessionToken([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
