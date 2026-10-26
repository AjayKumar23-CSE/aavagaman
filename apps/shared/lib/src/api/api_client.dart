import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/auth_tokens.dart';
import '../models/health.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'token_store.dart';

class ApiClient {
  ApiClient({
    required this.config,
    required this.tokens,
    void Function()? onSessionExpired,
    HttpClientAdapter? adapter,
  })  : dio = _build(config, adapter),
        _plain = _build(config, adapter),
        uploadDio = _buildUpload(adapter) {
    refresher = TokenRefresher(plainDio: _plain, tokens: tokens, onSessionExpired: onSessionExpired);
    dio.interceptors.add(AuthInterceptor(
      tokens: tokens,
      plainDio: _plain,
      onSessionExpired: onSessionExpired,
      refresher: refresher,
    ));
  }

  final AppConfig config;
  final TokenStore tokens;

  /// Authenticated client rooted at `/v1`.
  final Dio dio;
  final Dio _plain;

  /// Bare client for presigned object-storage PUTs: no base URL, no auth
  /// header (the URL carries its own signature).
  final Dio uploadDio;

  /// Shared with the WebSocket client so a refresh never runs twice.
  late final TokenRefresher refresher;

  /// Current access token, or null when logged out.
  Future<String?> accessToken() async => (await tokens.read())?.accessToken;

  /// Rotates the tokens after the WebSocket handshake was rejected with
  /// `UNAUTHORIZED`. Returns the new access token, or null when the session
  /// is over (tokens cleared, `onSessionExpired` fired) or there is none.
  /// Throws [ApiException] on network errors.
  Future<String?> refreshTokens({String? staleAccessToken}) async {
    try {
      final AuthTokens? fresh = await refresher.refresh(staleAccessToken: staleAccessToken);
      return fresh?.accessToken;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return null;
      throw ApiException.fromDio(e);
    }
  }

  static Dio _buildUpload(HttpClientAdapter? adapter) {
    final d = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
    ));
    if (adapter != null) d.httpClientAdapter = adapter;
    return d;
  }

  static Dio _build(AppConfig config, HttpClientAdapter? adapter) {
    final d = Dio(BaseOptions(
      baseUrl: config.restBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ));
    if (adapter != null) d.httpClientAdapter = adapter;
    return d;
  }

  /// `/health` sits outside `/v1`; a 503 still carries the report.
  Future<Health> health() async {
    final res = await _plain.getUri<Map<String, dynamic>>(
      Uri.parse('${config.apiBaseUrl}/health'),
      options: Options(validateStatus: (s) => s == 200 || s == 503),
    );
    return Health.fromJson(res.data!);
  }
}
