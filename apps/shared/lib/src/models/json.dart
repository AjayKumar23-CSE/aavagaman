/// Lenient JSON readers. PostgreSQL NUMERIC columns arrive as strings from
/// the API, timestamps as ISO-8601 strings.
library;

double? asDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int? asInt(Object? v) => switch (v) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

DateTime? asInstant(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `Map<dynamic, dynamic>` from a socket payload → `Map<String, dynamic>`.
Map<String, dynamic>? asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : null;
