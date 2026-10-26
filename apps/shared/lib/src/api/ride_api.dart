import '../models/earnings.dart';
import '../models/payment.dart';
import '../models/receipt.dart';
import '../models/ride.dart';
import '../models/vehicle_type.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// SPEC §7.2 ride endpoints (rider) and §7.3 presence / offer / trip
/// endpoints (driver). Every method throws [ApiException] on failure.
class RideApi {
  RideApi(this._client);

  final ApiClient _client;

  // ------------------------------------------------------------------ rider

  /// `POST /fare/estimate`. 503 `ROUTING_UNAVAILABLE` when no route exists.
  Future<FareEstimate> estimate({required RidePlace pickup, required RidePlace drop}) =>
      guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(
          '/fare/estimate',
          data: {'pickup': pickup.toJson(), 'drop': drop.toJson()},
        );
        return FareEstimate.fromJson(res.data!);
      });

  /// `GET /drivers/nearby` — up to 10 anonymised idle cars.
  Future<List<NearbyDriver>> nearby({required double lat, required double lng}) =>
      guardApi(() async {
        final res = await _client.dio.get<List<dynamic>>(
          '/drivers/nearby',
          queryParameters: {'lat': lat, 'lng': lng},
        );
        return [
          for (final d in res.data ?? const [])
            NearbyDriver.fromJson((d as Map).cast<String, dynamic>()),
        ];
      });

  /// `POST /rides`. 422 `OUTSIDE_SERVICE_AREA`, 409 `ACTIVE_RIDE_EXISTS`,
  /// 422 `FARE_CONFIG_INVALID` (get a new estimate), 503 `ROUTING_UNAVAILABLE`.
  Future<Ride> create({
    required RidePlace pickup,
    required RidePlace drop,
    required String fareConfigId,
    required PaymentMethod paymentMethod,
    VehicleType vehicleType = VehicleType.sedan,
  }) =>
      guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>('/rides', data: {
          'pickup': pickup.toJson(),
          'drop': drop.toJson(),
          'fare_config_id': fareConfigId,
          'vehicle_type': vehicleType.wire,
          'payment_method': paymentMethod.name,
        });
        return Ride.fromJson(res.data!);
      });

  /// `GET /rides/active`; null on 404 `NO_ACTIVE_RIDE`.
  Future<Ride?> active() => _activeOrNull('/rides/active');

  /// `GET /rides/:id`.
  Future<Ride> get(String id) => guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>('/rides/$id');
        return Ride.fromJson(res.data!);
      });

  /// `POST /rides/:id/cancel` — allowed through ARRIVED (SPEC §9.5): free
  /// while REQUESTED or within 120 s of accept, otherwise the returned ride
  /// carries `cancellation_fee`. 409 `RIDE_NOT_CANCELLABLE` from STARTED.
  Future<Ride> cancel(String id, {String? reason}) => guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(
          '/rides/$id/cancel',
          data: {'reason': ?reason},
        );
        return Ride.fromJson(res.data!);
      });

  /// `GET /rides?page=&limit=` — newest first.
  Future<RidePageResult> history({int page = 1, int limit = 20}) =>
      _page('/rides', page: page, limit: limit);

  /// `GET /rides/:id/receipt`. 409 `RECEIPT_NOT_READY` unless COMPLETED/PAID.
  Future<RideReceipt> receipt(String id) => guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>('/rides/$id/receipt');
        return RideReceipt.fromJson(res.data!);
      });

  /// `POST /rides/:id/rating` (201). 409 `ALREADY_RATED`, 409 `RIDE_NOT_RATEABLE`.
  Future<RatingResult> rate(String id, {required int stars, String? comment}) =>
      guardApi(() async {
        final trimmed = comment?.trim();
        final res = await _client.dio.post<Map<String, dynamic>>('/rides/$id/rating', data: {
          'stars': stars,
          if (trimmed != null && trimmed.isNotEmpty) 'comment': trimmed,
        });
        return RatingResult.fromJson(res.data!);
      });

  /// `POST /rides/:id/call` (rider) or `POST /driver/rides/:id/call` (driver):
  /// the server rings the caller from the Aavagaman number, then bridges the
  /// other party (D-058). 409 `RIDE_NOT_CALLABLE`, 429 `CALL_TOO_SOON`,
  /// 502 `CALL_FAILED`, 503 `CALLS_UNAVAILABLE`.
  Future<RideCall> requestCall(String id, {bool driver = false}) => guardApi(() async {
        final res = await _client.dio
            .post<Map<String, dynamic>>(driver ? '/driver/rides/$id/call' : '/rides/$id/call');
        return RideCall.fromJson(res.data!);
      });

  /// `POST /rides/:id/sos {lat,lng}` (201) — rider or driver of the ride.
  Future<void> sos(String id, {required double lat, required double lng}) =>
      guardApi(() => _client.dio.post<void>('/rides/$id/sos', data: {'lat': lat, 'lng': lng}));

  // ----------------------------------------------------------------- driver

  /// `POST /driver/online`. 403 `NOT_ELIGIBLE`.
  Future<void> driverOnline({required double lat, required double lng}) => guardApi(
      () => _client.dio.post<void>('/driver/online', data: {'lat': lat, 'lng': lng}));

  /// `POST /driver/offline`. 409 `ON_TRIP`.
  Future<void> driverOffline() => guardApi(() => _client.dio.post<void>('/driver/offline'));

  /// `POST /driver/location` — REST fallback for `driver:location`.
  /// 409 `DRIVER_OFFLINE`: the heartbeat expired, call [driverOnline] again.
  Future<void> driverLocation(DriverFix fix) =>
      guardApi(() => _client.dio.post<void>('/driver/location', data: fix.toJson()));

  /// `GET /driver/rides/active`; null on 404 `NO_ACTIVE_RIDE`.
  Future<Ride?> driverActive() => _activeOrNull('/driver/rides/active');

  /// `POST /driver/rides/:id/accept`. 409 `OFFER_NOT_VALID` / `DRIVER_BUSY`.
  Future<Ride> driverAccept(String id) => guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>('/driver/rides/$id/accept');
        return Ride.fromJson(res.data!);
      });

  /// `POST /driver/rides/:id/reject` (204).
  Future<void> driverReject(String id) =>
      guardApi(() => _client.dio.post<void>('/driver/rides/$id/reject'));

  // ------------------------------------------------------------ driver trip

  /// `POST /driver/rides/:id/arrived {lat,lng}` → ARRIVED. 422
  /// `TOO_FAR_FROM_PICKUP` ("You are N m from the pickup; get within 300 m").
  Future<Ride> driverArrived(String id, {required double lat, required double lng}) =>
      _tripPost('/driver/rides/$id/arrived', {'lat': lat, 'lng': lng});

  /// `POST /driver/rides/:id/start {otp,lat,lng}` → STARTED. 401 `OTP_INVALID`
  /// ("Wrong OTP. 2 attempts left."), 401 `OTP_LOCKED` after 3 wrong.
  Future<Ride> driverStart(String id,
          {required String otp, required double lat, required double lng}) =>
      _tripPost('/driver/rides/$id/start', {'otp': otp, 'lat': lat, 'lng': lng});

  /// `POST /driver/rides/:id/complete {lat,lng}` → COMPLETED with `final_fare`,
  /// `cancellation_fee`, `amount_due`, actual distance and duration.
  Future<Ride> driverComplete(String id, {required double lat, required double lng}) =>
      _tripPost('/driver/rides/$id/complete', {'lat': lat, 'lng': lng});

  /// `POST /driver/rides/:id/cancel {reason}`. Returns the ride either as
  /// `REQUESTED` with no driver (re-queued; counts against the driver) or
  /// `CANCELLED` (no-show after 300 s at the pickup; the rider pays the
  /// fee). 409 `INVALID_TRANSITION` once STARTED.
  Future<Ride> driverCancel(String id, {required String reason}) =>
      _tripPost('/driver/rides/$id/cancel', {'reason': reason});

  /// `POST /driver/rides/:id/cash-collected` → PAID. 409 `PAYMENT_PENDING`
  /// (rider started an online payment < 5 min ago), 409 `ALREADY_PAID`.
  Future<Ride> driverCashCollected(String id) =>
      _tripPost('/driver/rides/$id/cash-collected', null);

  /// `POST /driver/rides/:id/rating {stars}` (201). 409 `ALREADY_RATED`.
  Future<RatingResult> driverRate(String id, {required int stars}) => guardApi(() async {
        final res = await _client.dio
            .post<Map<String, dynamic>>('/driver/rides/$id/rating', data: {'stars': stars});
        return RatingResult.fromJson(res.data!);
      });

  /// `GET /driver/rides?page=&limit=` — newest first.
  Future<RidePageResult> driverHistory({int page = 1, int limit = 20}) =>
      _page('/driver/rides', page: page, limit: limit);

  /// `GET /driver/earnings?period=today|week`.
  Future<DriverEarnings> driverEarnings(EarningsPeriod period) => guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>(
          '/driver/earnings',
          queryParameters: {'period': period.name},
        );
        return DriverEarnings.fromJson(res.data!);
      });

  Future<Ride> _tripPost(String path, Map<String, dynamic>? body) => guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(path, data: body);
        return Ride.fromJson(res.data!);
      });

  Future<RidePageResult> _page(String path, {required int page, required int limit}) =>
      guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>(
          path,
          queryParameters: {'page': page, 'limit': limit},
        );
        return RidePageResult.fromJson(res.data!);
      });

  Future<Ride?> _activeOrNull(String path) async {
    try {
      return await guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>(path);
        return Ride.fromJson(res.data!);
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
