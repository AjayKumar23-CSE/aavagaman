/// Mirrors the `ride_status` enum (SPEC §5, §10).
enum RideStatus {
  requested('REQUESTED'),
  accepted('ACCEPTED'),
  arrived('ARRIVED'),
  started('STARTED'),
  completed('COMPLETED'),
  paid('PAID'),
  cancelled('CANCELLED'),
  noDriver('NO_DRIVER');

  const RideStatus(this.wire);

  final String wire;

  static RideStatus fromWire(String value) =>
      values.firstWhere((s) => s.wire == value,
          orElse: () => throw ArgumentError.value(value, 'RideStatus'));

  /// Driver is assigned and the trip has not ended.
  bool get isActive => this == accepted || this == arrived || this == started;

  bool get isTerminal => this == paid || this == cancelled || this == noDriver;
}
