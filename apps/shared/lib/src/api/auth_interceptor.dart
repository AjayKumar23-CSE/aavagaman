import 'dart:async';

import 'package:dio/dio.dart';

import '../models/auth_tokens.dart';
import 'token_store.dart';

/// Rotates the refresh token (`POST /auth/refresh`, SPEC §7.1) exactly once
/// at a time.
///
/// The server treats a concurrent rotation of the same refresh token as
/// reuse and revokes every token of the user (SPEC §16), so the REST
/// interceptor and the WebSocket client must share one instance.
class TokenRefresher {
  TokenRefresher({required this.plainDio, required this.tokens, this.onSessionExpired});

  /// Dio without interceptors, rooted at `/v1`.
  final Dio plainDio;
  final TokenStore tokens;

  /// Called when the refresh token is rejected (expired, revoked or reused).
  final void Function()? onSessionExpired;

  Future<AuthTokens?>? _inflight;

  /// Returns the current tokens, rotating them when needed.
  ///
  /// [staleAccessToken] is the access token the caller just saw rejected.
  /// If the store already holds a different one, somebody else rotated in
  /// the meantime and those tokens are returned without a network call.
  /// Returns null when there is no session. Throws [DioException] when the
  /// refresh call fails; on 401/403 the tokens are cleared first and
  /// [onSessionExpired] fires.
  Future<AuthTokens?> refresh({String? staleAccessToken}) {
    final running = _inflight;
    if (running != null) return running;
    final f = _run(staleAccessToken);
    _inflight = f;
    f.whenComplete(() => _inflight = null).ignore();
    return f;
  }

  Future<AuthTokens?> _run(String? staleAccessToken) async {
    final current = await tokens.read();
    if (current == null) return null;
    if (staleAccessToken != null && current.accessToken != staleAccessToken) return current;
    try {
      final res = await plainDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': current.refreshToken},
      );
      final fresh = AuthTokens.fromJson(res.data!);
      await tokens.write(fresh);
      return fresh;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // A network failure keeps the tokens for the next attempt.
      if (status == 401 || status == 403) {
        await tokens.clear();
        onSessionExpired?.call();
      }
      rethrow;
    }
  }
}

/// Adds the bearer token and transparently refreshes it on 401
/// (SPEC §7.1 rotating refresh tokens).
///
/// [QueuedInterceptor] serialises errors, so concurrent 401s trigger a single
/// refresh; later requests see the rotated token and just retry.
/// [plainDio] has no interceptors and is used for the refresh call and for
/// retries, so a retried 401 can never deadlock this queue.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.tokens,
    required this.plainDio,
    this.onSessionExpired,
    TokenRefresher? refresher,
  }) : refresher = refresher ??
            TokenRefresher(plainDio: plainDio, tokens: tokens, onSessionExpired: onSessionExpired);

  /// Set `options.extra[skipAuth] = true` for public endpoints.
  static const skipAuth = 'skipAuth';
  static const _retried = '_authRetried';

  final TokenStore tokens;
  final Dio plainDio;
  final void Function()? onSessionExpired;
  final TokenRefresher refresher;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[skipAuth] != true) {
      final t = await tokens.read();
      if (t != null) options.headers['Authorization'] = 'Bearer ${t.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        options.extra[skipAuth] == true ||
        options.extra[_retried] == true) {
      return handler.next(err);
    }

    final sent = options.headers['Authorization'] as String?;
    final stale = sent != null && sent.startsWith('Bearer ') ? sent.substring(7) : null;

    try {
      // Only refresh if nobody else already did while this request was in flight.
      final fresh = await refresher.refresh(staleAccessToken: stale);
      if (fresh == null) return handler.next(err);
      options.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      options.extra[_retried] = true;
      handler.resolve(await plainDio.fetch(options));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Refresh token rejected → session is over; report the original 401.
      if (e.requestOptions.path == '/auth/refresh' && (status == 401 || status == 403)) {
        return handler.next(err);
      }
      handler.next(e);
    }
  }
}
