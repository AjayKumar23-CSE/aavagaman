class Health {
  const Health({
    required this.ok,
    required this.db,
    required this.redis,
    required this.osrm,
  });

  factory Health.fromJson(Map<String, dynamic> json) => Health(
        ok: json['status'] == 'ok',
        db: json['db'] == true,
        redis: json['redis'] == true,
        osrm: json['osrm'] == true,
      );

  final bool ok;
  final bool db;
  final bool redis;
  final bool osrm;
}
