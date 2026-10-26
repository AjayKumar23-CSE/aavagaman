import 'package:flutter/material.dart';

/// Vehicle classes a rider can choose between (D-056), in display order.
enum VehicleType {
  bike(seats: 1, icon: Icons.two_wheeler_rounded),
  auto(seats: 3, icon: Icons.electric_rickshaw_rounded),
  mini(seats: 4, icon: Icons.directions_car_rounded),
  sedan(seats: 4, icon: Icons.directions_car_filled_rounded);

  const VehicleType({required this.seats, required this.icon});

  /// Passenger seats, as the server reports them.
  final int seats;
  final IconData icon;

  /// Wire value (`vehicle_type`).
  String get wire => name;

  static const fallback = VehicleType.sedan;

  static VehicleType? tryParse(String? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }

  static VehicleType parse(String? wire) => tryParse(wire) ?? fallback;
}
