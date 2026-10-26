/// Indian mobile number helpers, mirroring the backend's
/// `normalizeIndianPhone` (backend/src/common/phone.ts).
class IndianPhone {
  const IndianPhone._();

  static final _e164 = RegExp(r'^\+91[6-9]\d{9}$');
  static final _separators = RegExp(r'[\s\-()]');

  /// Accepts "98xxxxxxxx", "098…", "91…" and "+91 98…"; returns E.164
  /// (`+9198xxxxxxxx`) or null when it is not an Indian mobile number.
  static String? normalize(String input) {
    var n = input.replaceAll(_separators, '');
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(n)) {
      n = '+91$n';
    } else if (RegExp(r'^0[6-9]\d{9}$').hasMatch(n)) {
      n = '+91${n.substring(1)}';
    } else if (RegExp(r'^91[6-9]\d{9}$').hasMatch(n)) {
      n = '+$n';
    }
    return _e164.hasMatch(n) ? n : null;
  }

  static bool isValid(String input) => normalize(input) != null;

  /// "+919812345678" → "+91 98123 45678". Other input is returned unchanged.
  static String format(String phone) {
    final n = normalize(phone);
    if (n == null) return phone;
    return '+91 ${n.substring(3, 8)} ${n.substring(8)}';
  }
}
