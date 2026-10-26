import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/auth_api.dart';
import '../models/user.dart';
import '../providers.dart';

/// Who is using the app. Drives go_router redirects in both apps.
sealed class SessionState {
  const SessionState();
}

/// Not yet restored from secure storage (Splash).
class SessionUnknown extends SessionState {
  const SessionUnknown();
}

class SessionLoggedOut extends SessionState {
  const SessionLoggedOut();
}

class SessionLoggedIn extends SessionState {
  const SessionLoggedIn(this.user);

  final User user;
}

final sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  StreamSubscription<String>? _tokenRefresh;

  @override
  SessionState build() {
    ref.onDispose(() => _tokenRefresh?.cancel());
    return const SessionUnknown();
  }

  User? get user => switch (state) {
        SessionLoggedIn(:final user) => user,
        _ => null,
      };

  /// Splash: tokens present → `GET /me`, else logged out.
  /// Throws [ApiException] on network errors so Splash can offer a retry.
  Future<void> restore() async {
    final store = ref.read(tokenStoreProvider);
    if (await store.read() == null) {
      state = const SessionLoggedOut();
      return;
    }
    try {
      final user = await ref.read(meApiProvider).get();
      _loggedIn(user);
      // SPEC §14: register the FCM token on every app start.
      unawaited(_sendPushToken());
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await store.clear();
        state = const SessionLoggedOut();
        return;
      }
      rethrow;
    }
  }

  /// `POST /auth/otp/verify`, then persists tokens and logs in.
  Future<User> verifyOtp({
    required String phone,
    required String code,
    required LoginRole role,
  }) async {
    final fcmToken = await ref.read(pushTokenSourceProvider).getToken();
    final version = await ref.read(appVersionProvider.future);
    final result = await ref.read(authApiProvider).verifyOtp(
          phone: phone,
          code: code,
          role: role,
          device: DeviceInfo(fcmToken: fcmToken, appVersion: version),
        );
    await ref.read(tokenStoreProvider).write(result.tokens);
    _loggedIn(result.user);
    return result.user;
  }

  /// After `PATCH /me` or anything else that returns a fresh user.
  void setUser(User user) => state = SessionLoggedIn(user);

  Future<void> logout() async {
    try {
      await ref.read(authApiProvider).logout();
    } on ApiException catch (e) {
      // Still log out locally; the refresh token expires on its own.
      debugPrint('Logout request failed: $e');
    }
    await _clear();
  }

  /// `DELETE /me`. Throws [ApiException] (e.g. 409 `ACTIVE_RIDE`) and stays
  /// logged in on failure.
  Future<void> deleteAccount() async {
    await ref.read(meApiProvider).delete();
    await _clear();
  }

  /// Called by the API client when the refresh token is rejected.
  void expire() {
    _stopTokenRefresh();
    state = const SessionLoggedOut();
  }

  void _loggedIn(User user) {
    state = SessionLoggedIn(user);
    _tokenRefresh ??= ref
        .read(pushTokenSourceProvider)
        .onTokenRefresh
        .listen((token) => _sendPushToken(token));
  }

  Future<void> _sendPushToken([String? token]) async {
    try {
      token ??= await ref.read(pushTokenSourceProvider).getToken();
      if (token == null || state is! SessionLoggedIn) return;
      await ref.read(meApiProvider).registerFcmToken(token);
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  Future<void> _clear() async {
    _stopTokenRefresh();
    await ref.read(tokenStoreProvider).clear();
    state = const SessionLoggedOut();
  }

  void _stopTokenRefresh() {
    unawaited(_tokenRefresh?.cancel());
    _tokenRefresh = null;
  }
}
