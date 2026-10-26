/// Ride models (SPEC §5 rides, §7.2 / §7.3 ride JSON, §8 events).
library;

import 'json.dart';
import 'ride_status.dart';
import 'vehicle_type.dart';

enum PaymentMethod {
  cash,
  online;

  static PaymentMethod fromWire(Object? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => cash);
}

/// Who cancelled a ride (`cancel_actor`).
enum CancelActor {
  rider,
  driver,
  admin,
  system;

  static CancelActor? tryParse(Object? v) {
    for (final a in values) {
      if (a.name == v) return a;
    }
    return null;
  }
}

/// A pickup or drop point.
class RidePlace {
  const RidePlace({required this.lat, required this.lng, required this.address});

  factory RidePlace.fromJson(Map<String, dynamic> json) => RidePlace(
        lat: asDouble(json['lat'])!,
        lng: asDouble(json['lng'])!,
        address: json['address'] as String? ?? '',
      );

  final double lat;
  final double lng;
  final String address;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'address': address};

  @override
  bool operator ==(Object other) =>
      other is RidePlace && other.lat == lat && other.lng == lng && other.address == address;

  @override
  int get hashCode => Object.hash(lat, lng, address);

  @override
  String toString() => 'RidePlace($lat, $lng, $address)';
}

/// Vehicle as shown to the rider (no id; SPEC §8 `driver.vehicle`).
class RideVehicle {
  const RideVehicle({
    required this.regNumber,
    required this.make,
    required this.model,
    required this.colour,
  });

  factory RideVehicle.fromJson(Map<String, dynamic> json) => RideVehicle(
        regNumber: json['reg_number'] as String? ?? '',
        make: json['make'] as String? ?? '',
        model: json['model'] as String? ?? '',
        colour: json['colour'] as String? ?? '',
      );

  final String regNumber;
  final String make;
  final String model;
  final String colour;

  /// "White Maruti Suzuki Dzire".
  String get label => [colour, make, model].where((s) => s.isNotEmpty).join(' ');
}

/// Driver public info on a ride. [phone] is only present from ARRIVED
/// (SPEC §16); [phoneMasked] is always there.
class RideDriver {
  const RideDriver({
    required this.id,
    this.name,
    this.rating,
    required this.phoneMasked,
    this.phone,
    this.callVia,
    this.vehicle,
  });

  factory RideDriver.fromJson(Map<String, dynamic> json) => RideDriver(
        id: json['id'] as String,
        name: json['name'] as String?,
        rating: asDouble(json['rating']),
        phoneMasked: json['phone_masked'] as String? ?? '',
        phone: json['phone'] as String?,
        callVia: json['call_via'] as String?,
        vehicle: json['vehicle'] is Map
            ? RideVehicle.fromJson(asMap(json['vehicle'])!)
            : null,
      );

  final String id;
  final String? name;
  final double? rating;
  final String phoneMasked;
  final String? phone;

  /// The Aavagaman number a bridged call shows (D-058); set while the trip is
  /// live when masked calling is on. The real number then never arrives.
  final String? callVia;
  final RideVehicle? vehicle;

  /// The dialer may only be offered once the server reveals the number.
  bool get canCall => phone != null && phone!.isNotEmpty;

  /// Call through the app (server bridges both parties).
  bool get canBridge => callVia != null && callVia!.isNotEmpty;
}

/// Rider public info in the driver view of a ride.
class RideRider {
  const RideRider({
    required this.id,
    this.name,
    this.rating,
    required this.phoneMasked,
    this.phone,
    this.callVia,
  });

  factory RideRider.fromJson(Map<String, dynamic> json) => RideRider(
        id: json['id'] as String,
        name: json['name'] as String?,
        rating: asDouble(json['rating']),
        phoneMasked: json['phone_masked'] as String? ?? '',
        phone: json['phone'] as String?,
        callVia: json['call_via'] as String?,
      );

  final String id;
  final String? name;
  final double? rating;
  final String phoneMasked;
  final String? phone;

  /// See [RideDriver.callVia].
  final String? callVia;

  bool get canCall => phone != null && phone!.isNotEmpty;
  bool get canBridge => callVia != null && callVia!.isNotEmpty;
}

/// A call the server bridged through the Aavagaman number (D-058).
class RideCall {
  const RideCall({required this.id, required this.status, required this.via});

  factory RideCall.fromJson(Map<String, dynamic> json) => RideCall(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'initiated',
        via: json['via'] as String? ?? '',
      );

  final String id;
  final String status;

  /// The number that rings the caller (and that both parties see).
  final String via;
}

/// A ride as returned by `GET /rides/:id`, `POST /rides`,
/// `GET /driver/rides/active`, … Rider-only fields ([tripOtp], [shareToken])
/// are null in the driver view; [rider] is null in the rider view.
class Ride {
  const Ride({
    required this.id,
    required this.status,
    required this.pickup,
    required this.drop,
    this.vehicleType = 'sedan',
    this.paymentMethod = PaymentMethod.cash,
    this.estDistanceM,
    this.estDurationS,
    this.estFareMin,
    this.estFareMax,
    this.actualDistanceM,
    this.actualDurationS,
    this.finalFare,
    this.cancellationFee,
    this.amountDue,
    this.cancelledBy,
    this.cancelReason,
    this.fareConfigId,
    this.requestedAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.paidAt,
    this.cancelledAt,
    this.tripOtp,
    this.shareToken,
    this.driver,
    this.rider,
    this.earning,
  });

  factory Ride.fromJson(Map<String, dynamic> json) => Ride(
        id: json['id'] as String,
        status: RideStatus.fromWire(json['status'] as String),
        vehicleType: json['vehicle_type'] as String? ?? 'sedan',
        paymentMethod: PaymentMethod.fromWire(json['payment_method']),
        pickup: RidePlace.fromJson(asMap(json['pickup'])!),
        drop: RidePlace.fromJson(asMap(json['drop'])!),
        estDistanceM: asInt(json['est_distance_m']),
        estDurationS: asInt(json['est_duration_s']),
        estFareMin: asDouble(json['est_fare_min']),
        estFareMax: asDouble(json['est_fare_max']),
        actualDistanceM: asInt(json['actual_distance_m']),
        actualDurationS: asInt(json['actual_duration_s']),
        finalFare: asDouble(json['final_fare']),
        cancellationFee: asDouble(json['cancellation_fee']),
        amountDue: asDouble(json['amount_due']),
        cancelledBy: CancelActor.tryParse(json['cancelled_by']),
        cancelReason: json['cancel_reason'] as String?,
        fareConfigId: json['fare_config_id'] as String?,
        requestedAt: asInstant(json['requested_at']),
        acceptedAt: asInstant(json['accepted_at']),
        arrivedAt: asInstant(json['arrived_at']),
        startedAt: asInstant(json['started_at']),
        completedAt: asInstant(json['completed_at']),
        paidAt: asInstant(json['paid_at']),
        cancelledAt: asInstant(json['cancelled_at']),
        tripOtp: json['trip_otp'] as String?,
        shareToken: json['share_token'] as String?,
        driver: json['driver'] is Map ? RideDriver.fromJson(asMap(json['driver'])!) : null,
        rider: json['rider'] is Map ? RideRider.fromJson(asMap(json['rider'])!) : null,
        earning: json['earning'] is Map ? RideEarning.fromJson(asMap(json['earning'])!) : null,
      );

  final String id;
  final RideStatus status;
  final String vehicleType;
  final PaymentMethod paymentMethod;
  final RidePlace pickup;
  final RidePlace drop;
  final int? estDistanceM;
  final int? estDurationS;
  final double? estFareMin;
  final double? estFareMax;
  final int? actualDistanceM;
  final int? actualDurationS;
  final double? finalFare;

  /// Fee charged on this ride: a rider's late cancel sets it on the cancelled
  /// ride, and it is carried onto the next completed ride as a line item
  /// (SPEC §9.5).
  final double? cancellationFee;

  /// `final_fare + cancellation_fee`; null until COMPLETED.
  final double? amountDue;
  final CancelActor? cancelledBy;
  final String? cancelReason;
  final String? fareConfigId;
  final DateTime? requestedAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;

  /// 4 digits; rider view only, and only while ACCEPTED / ARRIVED.
  final String? tripOtp;
  final String? shareToken;
  final RideDriver? driver;
  final RideRider? rider;

  /// Driver history only: the fare split for the Earnings list.
  final RideEarning? earning;

  /// Still searching for a driver.
  bool get isSearching => status == RideStatus.requested;

  /// What the rider owes once the trip is complete (falls back to the fare
  /// plus fee when the server did not send `amount_due`).
  double? get dueAmount =>
      amountDue ?? (finalFare == null ? null : finalFare! + (cancellationFee ?? 0));

  /// The receipt endpoint answers for these (`RECEIPT_NOT_READY` otherwise).
  bool get hasReceipt => status == RideStatus.completed || status == RideStatus.paid;

  /// Both parties may rate once the trip is complete (`RIDE_NOT_RATEABLE`).
  bool get isRateable => hasReceipt;

  /// Timestamp of the latest transition, for history lists.
  DateTime? get lastEventAt =>
      cancelledAt ?? paidAt ?? completedAt ?? startedAt ?? arrivedAt ?? acceptedAt ?? requestedAt;

  Ride copyWith({
    RideStatus? status,
    RideDriver? driver,
    bool clearDriver = false,
    double? finalFare,
    double? cancellationFee,
    double? amountDue,
    CancelActor? cancelledBy,
    String? cancelReason,
    String? tripOtp,
    bool clearTripOtp = false,
    DateTime? acceptedAt,
    bool clearAcceptedAt = false,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? paidAt,
    DateTime? cancelledAt,
  }) =>
      Ride(
        id: id,
        status: status ?? this.status,
        vehicleType: vehicleType,
        paymentMethod: paymentMethod,
        pickup: pickup,
        drop: drop,
        estDistanceM: estDistanceM,
        estDurationS: estDurationS,
        estFareMin: estFareMin,
        estFareMax: estFareMax,
        actualDistanceM: actualDistanceM,
        actualDurationS: actualDurationS,
        finalFare: finalFare ?? this.finalFare,
        cancellationFee: cancellationFee ?? this.cancellationFee,
        amountDue: amountDue ?? this.amountDue,
        cancelledBy: cancelledBy ?? this.cancelledBy,
        cancelReason: cancelReason ?? this.cancelReason,
        fareConfigId: fareConfigId,
        requestedAt: requestedAt,
        acceptedAt: clearAcceptedAt ? null : (acceptedAt ?? this.acceptedAt),
        arrivedAt: arrivedAt ?? this.arrivedAt,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        paidAt: paidAt ?? this.paidAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        tripOtp: clearTripOtp ? null : (tripOtp ?? this.tripOtp),
        shareToken: shareToken,
        driver: clearDriver ? null : (driver ?? this.driver),
        rider: rider,
        earning: earning,
      );

  /// Merges a `ride:status` event into this ride. The event carries only the
  /// changed fields; callers usually re-fetch the ride afterwards for the
  /// timestamps. A `REQUESTED` event on an assigned ride means the driver
  /// cancelled and the ride was re-queued (SPEC §9.5): driver and OTP go.
  Ride apply(RideStatusEvent e, {DateTime? now}) {
    if (e.rideId != id) return this;
    final at = now ?? DateTime.now();
    final becameAccepted = status == RideStatus.requested && e.status == RideStatus.accepted;
    final requeued = status != RideStatus.requested && e.status == RideStatus.requested;
    final keepsOtp = e.status == RideStatus.accepted || e.status == RideStatus.arrived;
    return copyWith(
      status: e.status,
      driver: e.driver,
      clearDriver: requeued,
      finalFare: e.finalFare,
      cancellationFee: e.cancellationFee,
      amountDue: e.amountDue,
      cancelledBy: e.cancelledBy,
      cancelReason: e.cancelReason,
      tripOtp: e.tripOtp,
      clearTripOtp: e.tripOtp == null && !keepsOtp,
      acceptedAt: becameAccepted ? at : null,
      clearAcceptedAt: requeued,
      arrivedAt: status != e.status && e.status == RideStatus.arrived ? at : null,
      startedAt: status != e.status && e.status == RideStatus.started ? at : null,
      completedAt: status != e.status && e.status == RideStatus.completed ? at : null,
      paidAt: status != e.status && e.status == RideStatus.paid ? at : null,
      cancelledAt: status != e.status && e.status == RideStatus.cancelled ? at : null,
    );
  }
}

/// `earning` on `GET /driver/rides` items: the fare, the platform's
/// commission (on the fare excluding GST), the GST, and what the driver keeps.
class RideEarning {
  const RideEarning({
    required this.fare,
    required this.commission,
    required this.gst,
    required this.net,
  });

  factory RideEarning.fromJson(Map<String, dynamic> json) => RideEarning(
        fare: asDouble(json['fare']) ?? 0,
        commission: asDouble(json['commission']) ?? 0,
        gst: asDouble(json['gst']) ?? 0,
        net: asDouble(json['net']) ?? 0,
      );

  final double fare;
  final double commission;
  final double gst;
  final double net;
}

/// One page of `GET /rides` / `GET /driver/rides` (`{data, page, limit, total}`).
class RidePageResult {
  const RidePageResult({
    required this.data,
    required this.page,
    required this.limit,
    required this.total,
  });

  factory RidePageResult.fromJson(Map<String, dynamic> json) => RidePageResult(
        data: [
          for (final r in (json['data'] as List? ?? const []))
            Ride.fromJson((r as Map).cast<String, dynamic>()),
        ],
        page: asInt(json['page']) ?? 1,
        limit: asInt(json['limit']) ?? 20,
        total: asInt(json['total']) ?? 0,
      );

  final List<Ride> data;
  final int page;
  final int limit;
  final int total;

  /// More pages after this one.
  bool get hasMore => page * limit < total;
}

/// Rides loaded so far from a paginated history, for list screens.
class RidePages {
  const RidePages({
    this.rides = const [],
    this.page = 0,
    this.total = 0,
    this.loadingMore = false,
    this.error,
  });

  final List<Ride> rides;

  /// Last page loaded (0 = nothing yet).
  final int page;
  final int total;
  final bool loadingMore;

  /// Error from the last `loadMore`, shown inline with a retry.
  final Object? error;

  bool get hasMore => rides.length < total;

  Ride? byId(String id) {
    for (final r in rides) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Appends [next], skipping rides already present (a new ride may have
  /// shifted the pages between requests).
  RidePages append(RidePageResult next) {
    final seen = rides.map((r) => r.id).toSet();
    return RidePages(
      rides: [...rides, ...next.data.where((r) => !seen.contains(r.id))],
      page: next.page,
      total: next.total,
    );
  }

  RidePages copyWith({bool? loadingMore, Object? error, bool clearError = false}) => RidePages(
        rides: rides,
        page: page,
        total: total,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// One vehicle class on the confirm screen (D-056).
class FareOption {
  const FareOption({
    required this.vehicleType,
    required this.seats,
    required this.fareMin,
    required this.fareMax,
    required this.fareConfigId,
  });

  static FareOption? fromJson(Map<String, dynamic> json) {
    final type = VehicleType.tryParse(json['vehicle_type'] as String?);
    if (type == null) return null; // a class this build does not know
    return FareOption(
      vehicleType: type,
      seats: asInt(json['seats']) ?? type.seats,
      fareMin: asDouble(json['fare_min']) ?? 0,
      fareMax: asDouble(json['fare_max']) ?? 0,
      fareConfigId: json['fare_config_id'] as String,
    );
  }

  final VehicleType vehicleType;
  final int seats;
  final double fareMin;
  final double fareMax;
  final String fareConfigId;
}

/// `POST /fare/estimate` response: the route plus one [FareOption] per
/// vehicle class; the top-level fare fields belong to [vehicleType].
class FareEstimate {
  const FareEstimate({
    required this.distanceM,
    required this.durationS,
    required this.fareMin,
    required this.fareMax,
    required this.currency,
    required this.pickupInArea,
    required this.dropInArea,
    required this.fareConfigId,
    this.vehicleType = VehicleType.sedan,
    this.options = const [],
  });

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    final area = asMap(json['in_service_area']) ?? const {};
    final type = VehicleType.parse(json['vehicle_type'] as String?);
    final fareConfigId = json['fare_config_id'] as String;
    final options = <FareOption>[];
    for (final o in json['options'] as List<dynamic>? ?? const <dynamic>[]) {
      final m = asMap(o);
      final opt = m == null ? null : FareOption.fromJson(m);
      if (opt != null) options.add(opt);
    }
    return FareEstimate(
      distanceM: asInt(json['distance_m']) ?? 0,
      durationS: asInt(json['duration_s']) ?? 0,
      fareMin: asDouble(json['fare_min']) ?? 0,
      fareMax: asDouble(json['fare_max']) ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      pickupInArea: area['pickup'] != false,
      dropInArea: area['drop'] != false,
      fareConfigId: fareConfigId,
      vehicleType: type,
      // Servers before D-056 send no options: the single fare is the only choice.
      options: options.isNotEmpty
          ? options
          : [
              FareOption(
                vehicleType: type,
                seats: type.seats,
                fareMin: asDouble(json['fare_min']) ?? 0,
                fareMax: asDouble(json['fare_max']) ?? 0,
                fareConfigId: fareConfigId,
              ),
            ],
    );
  }

  /// The option for [type], or the default one.
  FareOption option(VehicleType type) {
    for (final o in options) {
      if (o.vehicleType == type) return o;
    }
    for (final o in options) {
      if (o.vehicleType == vehicleType) return o;
    }
    return options.first;
  }

  final int distanceM;
  final int durationS;
  final double fareMin;
  final double fareMax;
  final String currency;
  final bool pickupInArea;

  /// False → the Confirm screen shows the out-of-area notice (SPEC §11).
  final bool dropInArea;
  final String fareConfigId;
  final VehicleType vehicleType;
  final List<FareOption> options;
}

/// `GET /drivers/nearby` item. [driverId] is an opaque daily token (D-024).
class NearbyDriver {
  const NearbyDriver({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.heading,
  });

  factory NearbyDriver.fromJson(Map<String, dynamic> json) => NearbyDriver(
        driverId: json['driver_id'] as String,
        lat: asDouble(json['lat'])!,
        lng: asDouble(json['lng'])!,
        heading: asDouble(json['heading']) ?? 0,
      );

  final String driverId;
  final double lat;
  final double lng;
  final double heading;
}

/// `ride:offer` (SPEC §8).
class RideOffer {
  const RideOffer({
    required this.rideId,
    required this.pickup,
    required this.dropAddress,
    this.distanceToPickupM,
    required this.estFareMin,
    required this.estFareMax,
    required this.expiresAt,
  });

  factory RideOffer.fromJson(Map<String, dynamic> json) => RideOffer(
        rideId: json['ride_id'] as String,
        pickup: RidePlace.fromJson(asMap(json['pickup'])!),
        dropAddress: json['drop_address'] as String? ?? '',
        distanceToPickupM: asInt(json['distance_to_pickup_m']),
        estFareMin: asDouble(json['est_fare_min']) ?? 0,
        estFareMax: asDouble(json['est_fare_max']) ?? 0,
        expiresAt: asInstant(json['expires_at']) ?? DateTime.now(),
      );

  final String rideId;
  final RidePlace pickup;
  final String dropAddress;
  final int? distanceToPickupM;
  final double estFareMin;
  final double estFareMax;
  final DateTime expiresAt;

  Duration remaining([DateTime? now]) {
    final d = expiresAt.difference(now ?? DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}

/// `ride:status` (SPEC §8).
class RideStatusEvent {
  const RideStatusEvent({
    required this.rideId,
    required this.status,
    this.driver,
    this.finalFare,
    this.cancellationFee,
    this.amountDue,
    this.cancelledBy,
    this.cancelReason,
    this.tripOtp,
    this.reassigned = false,
  });

  factory RideStatusEvent.fromJson(Map<String, dynamic> json) => RideStatusEvent(
        rideId: json['ride_id'] as String,
        status: RideStatus.fromWire(json['status'] as String),
        driver: json['driver'] is Map ? RideDriver.fromJson(asMap(json['driver'])!) : null,
        finalFare: asDouble(json['final_fare']),
        cancellationFee: asDouble(json['cancellation_fee']),
        amountDue: asDouble(json['amount_due']),
        cancelledBy: CancelActor.tryParse(json['cancelled_by']),
        cancelReason: json['cancel_reason'] as String?,
        tripOtp: json['trip_otp'] as String?,
        reassigned: json['reassigned'] == true,
      );

  final String rideId;
  final RideStatus status;
  final RideDriver? driver;
  final double? finalFare;
  final double? cancellationFee;

  /// Present on COMPLETED / PAID events.
  final double? amountDue;
  final CancelActor? cancelledBy;
  final String? cancelReason;
  final String? tripOtp;

  /// Sent to a driver who just lost the ride: admin reassign, and also the
  /// driver's own cancel (the ride is re-queued to others).
  final bool reassigned;
}

/// `driver:position` (SPEC §8), for the rider's own ride.
class DriverPosition {
  const DriverPosition({
    required this.rideId,
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.heading,
    this.etaS,
  });

  factory DriverPosition.fromJson(Map<String, dynamic> json) => DriverPosition(
        rideId: json['ride_id'] as String? ?? '',
        driverId: json['driver_id'] as String? ?? '',
        lat: asDouble(json['lat'])!,
        lng: asDouble(json['lng'])!,
        heading: asDouble(json['heading']) ?? 0,
        etaS: asInt(json['eta_s']),
      );

  final String rideId;
  final String driverId;
  final double lat;
  final double lng;
  final double heading;

  /// Seconds to pickup (SPEC §9.7), only while ACCEPTED.
  final int? etaS;
}

/// A GPS fix sent by the driver (`driver:location` / `POST /driver/location`).
class DriverFix {
  const DriverFix({
    required this.lat,
    required this.lng,
    this.heading,
    this.speed,
    this.accuracy,
    this.ts,
  });

  factory DriverFix.fromJson(Map<String, dynamic> json) => DriverFix(
        lat: asDouble(json['lat'])!,
        lng: asDouble(json['lng'])!,
        heading: asDouble(json['heading']),
        speed: asDouble(json['speed']),
        accuracy: asDouble(json['accuracy']),
        ts: asInt(json['ts']),
      );

  final double lat;
  final double lng;

  /// Degrees 0–360.
  final double? heading;

  /// m/s, 0–100.
  final double? speed;

  /// Metres.
  final double? accuracy;

  /// Epoch milliseconds.
  final int? ts;

  /// Server DTO bounds (DriverFixDto): heading 0–360, speed 0–100, all ≥ 0.
  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (heading != null && heading! >= 0) 'heading': heading!.clamp(0, 360),
        if (speed != null && speed! >= 0) 'speed': speed!.clamp(0, 100),
        if (accuracy != null && accuracy! >= 0) 'accuracy': accuracy,
        if (ts != null) 'ts': ts,
      };
}
