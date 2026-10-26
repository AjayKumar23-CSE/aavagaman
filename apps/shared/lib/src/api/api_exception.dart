import 'package:dio/dio.dart';

/// Error in the API's `{ "error": { "code", "message", "details"? } }` shape
/// (SPEC §7).
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const [],
  });

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      final details = err['details'];
      return ApiException(
        code: err['code']?.toString() ?? 'HTTP_ERROR',
        message: err['message']?.toString() ?? 'Request failed',
        statusCode: e.response?.statusCode,
        details: details is List ? details.map((d) => d.toString()).toList() : const [],
      );
    }
    final network = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    return ApiException(
      code: network ? networkError : 'HTTP_ERROR',
      message: network ? 'No connection to server' : (e.message ?? 'Request failed'),
      statusCode: e.response?.statusCode,
    );
  }

  /// Wraps anything thrown by an API call.
  factory ApiException.from(Object error) => switch (error) {
        ApiException e => e,
        DioException e => ApiException.fromDio(e),
        _ => ApiException(code: 'UNKNOWN', message: error.toString()),
      };

  static const networkError = 'NETWORK_ERROR';

  final String code;
  final String message;
  final int? statusCode;

  /// Field-level messages for `VALIDATION_FAILED`.
  final List<String> details;

  /// What to show the user: the server message plus validation details.
  String get displayMessage =>
      details.isEmpty ? message : '$message:\n${details.map((d) => '• $d').join('\n')}';

  bool get isNetwork => code == networkError;

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}

/// Runs an API call and converts transport errors to [ApiException].
Future<T> guardApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
}
