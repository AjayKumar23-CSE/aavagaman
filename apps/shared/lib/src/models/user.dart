import 'json.dart';

enum UserRole { rider, driver, admin }

enum UserStatus { active, blocked }

class User {
  const User({
    required this.id,
    required this.phone,
    required this.role,
    required this.status,
    this.name,
    this.email,
    this.ratingAvg = 5.0,
    this.ratingCount = 0,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        phone: json['phone'] as String,
        name: json['name'] as String?,
        email: json['email'] as String?,
        role: UserRole.values.byName(json['role'] as String),
        status: UserStatus.values.byName(json['status'] as String? ?? 'active'),
        ratingAvg: asDouble(json['rating_avg']) ?? 5.0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] is String
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );

  final String id;
  final String phone;
  final String? name;
  final String? email;
  final UserRole role;
  final UserStatus status;
  final double ratingAvg;
  final int ratingCount;
  final DateTime? createdAt;

  /// First login: the rider app asks for a name before Home (SPEC §11).
  bool get needsName => name == null || name!.trim().isEmpty;
}
