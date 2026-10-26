/// `GET /rides/:id/receipt` (SPEC §7.2, §9.3 GST rules).
library;

import 'json.dart';
import 'ride.dart';
import 'ride_status.dart';

/// How the fare was built from the stored actuals.
class ReceiptComponents {
  const ReceiptComponents({
    required this.baseFare,
    required this.distance,
    required this.time,
    this.nightMultiplier,
    required this.raw,
    required this.minFareApplied,
    required this.capApplied,
    required this.cap,
  });

  factory ReceiptComponents.fromJson(Map<String, dynamic> json) => ReceiptComponents(
        baseFare: asDouble(json['base_fare']) ?? 0,
        distance: asDouble(json['distance']) ?? 0,
        time: asDouble(json['time']) ?? 0,
        nightMultiplier: asDouble(json['night_multiplier']),
        raw: asDouble(json['raw']) ?? 0,
        minFareApplied: json['min_fare_applied'] == true,
        capApplied: json['cap_applied'] == true,
        cap: asDouble(json['cap']) ?? 0,
      );

  final double baseFare;
  final double distance;
  final double time;

  /// Set when the night multiplier was applied (IST 23:00–05:00).
  final double? nightMultiplier;
  final double raw;
  final bool minFareApplied;

  /// The fare was capped at 1.25 × the estimate (drop unchanged).
  final bool capApplied;
  final double cap;
}

enum PaymentStatus {
  pending,
  paid,
  failed;

  static PaymentStatus fromWire(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => pending);
}

class RideReceipt {
  const RideReceipt({
    required this.rideId,
    required this.status,
    required this.currency,
    this.distanceM,
    this.durationS,
    required this.components,
    required this.fare,
    required this.gst,
    required this.fareExclGst,
    required this.cancellationFee,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    this.paidWith,
    this.paidAt,
    this.gstPct,
  });

  factory RideReceipt.fromJson(Map<String, dynamic> json) {
    final cfg = asMap(json['fare_config']) ?? const {};
    return RideReceipt(
      rideId: json['ride_id'] as String,
      status: RideStatus.fromWire(json['status'] as String),
      currency: json['currency'] as String? ?? 'INR',
      distanceM: asInt(json['distance_m']),
      durationS: asInt(json['duration_s']),
      components: ReceiptComponents.fromJson(asMap(json['components']) ?? const {}),
      fare: asDouble(json['fare']) ?? 0,
      gst: asDouble(json['gst']) ?? 0,
      fareExclGst: asDouble(json['fare_excl_gst']) ?? 0,
      cancellationFee: asDouble(json['cancellation_fee']) ?? 0,
      total: asDouble(json['total']) ?? 0,
      paymentMethod: PaymentMethod.fromWire(json['payment_method']),
      paymentStatus: PaymentStatus.fromWire(json['payment_status']),
      paidWith: json['paid_with'] as String?,
      paidAt: asInstant(json['paid_at']),
      gstPct: asDouble(cfg['gst_pct']),
    );
  }

  final String rideId;

  /// COMPLETED or PAID.
  final RideStatus status;
  final String currency;
  final int? distanceM;
  final int? durationS;
  final ReceiptComponents components;

  /// GST-inclusive trip fare (`final_fare`).
  final double fare;

  /// GST contained in [fare] (`fare - fare / (1 + gst_pct/100)`).
  final double gst;
  final double fareExclGst;

  /// Carried-over cancellation fee line (0 when none).
  final double cancellationFee;

  /// `fare + cancellation_fee`: what the rider pays.
  final double total;

  /// Chosen at booking: cash or online.
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;

  /// `cash`, `upi`, `card`, `wallet` once paid.
  final String? paidWith;
  final DateTime? paidAt;
  final double? gstPct;

  bool get isPaid => paymentStatus == PaymentStatus.paid;
  bool get hasCancellationFee => cancellationFee > 0;
}
