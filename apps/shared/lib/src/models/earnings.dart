/// `GET /driver/earnings?period=today|week` (SPEC §7.3, §15 settlements).
library;

import 'json.dart';

enum EarningsPeriod {
  today,
  week;

  static EarningsPeriod fromWire(Object? v) =>
      values.firstWhere((p) => p.name == v, orElse: () => today);
}

/// Totals over the driver's PAID rides in the period (IST day / Mon–Sun week).
class DriverEarnings {
  const DriverEarnings({
    required this.period,
    this.from,
    this.to,
    required this.rides,
    required this.gross,
    required this.commission,
    required this.gst,
    required this.net,
    required this.cashCollected,
    required this.online,
  });

  factory DriverEarnings.fromJson(Map<String, dynamic> json) => DriverEarnings(
        period: EarningsPeriod.fromWire(json['period']),
        from: asInstant(json['from']),
        to: asInstant(json['to']),
        rides: asInt(json['rides']) ?? 0,
        gross: asDouble(json['gross']) ?? 0,
        commission: asDouble(json['commission']) ?? 0,
        gst: asDouble(json['gst']) ?? 0,
        net: asDouble(json['net']) ?? 0,
        cashCollected: asDouble(json['cash_collected']) ?? 0,
        online: asDouble(json['online']) ?? 0,
      );

  /// Zero totals, for an empty state before the first load.
  const DriverEarnings.empty(this.period)
      : from = null,
        to = null,
        rides = 0,
        gross = 0,
        commission = 0,
        gst = 0,
        net = 0,
        cashCollected = 0,
        online = 0;

  final EarningsPeriod period;
  final DateTime? from;
  final DateTime? to;
  final int rides;

  /// Sum of `final_fare` (GST inclusive).
  final double gross;

  /// Platform commission on the fare excluding GST.
  final double commission;

  /// GST contained in [gross].
  final double gst;

  /// `gross - commission - gst`: the driver's take.
  final double net;

  /// Cash the driver already holds (fares plus carried cancellation fees).
  final double cashCollected;

  /// Collected online by the platform, paid out in the weekly settlement.
  final double online;
}
