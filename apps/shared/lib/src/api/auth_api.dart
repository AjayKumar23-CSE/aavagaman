import 'package:dio/dio.dart';

import '../models/auth_tokens.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Role a mobile app logs in as (`/auth/otp/*`).
enum LoginRole { rider, driver }

/// Sent as `device` on OTP verify.
class DeviceInfo {
  const DeviceInfo({this.platform = 'android', this.fcmToken, this.appVersion});

  final String platform;
  final String? fcmToken;
  final String? appVersion;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        if (fcmToken != null) 'fcm_token': fcmToken,
        if (appVersion != null) 'app_version': appVersion,
      };
}

class LoginResult {
  const LoginResult({required this.tokens, required this.user});

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        tokens: AuthTokens.fromJson(json),
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );

  final AuthTokens tokens;
  final User user;
}

/// SPEC §7.1 auth endpoints used by the mobile apps.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  static final _public = Options(extra: {AuthInterceptor.skipAuth: true});

  /// `POST /auth/otp/send`. Returns the code's time-to-live in seconds.
  /// Throws [ApiException] (`INVALID_PHONE`, 429 `OTP_RATE_LIMITED`).
  Future<int> sendOtp({required String phone, required LoginRole role}) => guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(
          '/auth/otp/send',
          data: {'phone': phone, 'role': role.name},
          options: _public,
        );
        return (res.data?['ttl'] as num?)?.toInt() ?? 300;
      });

  /// `POST /auth/otp/verify`. Does not persist tokens; see `SessionController`.
  /// Throws [ApiException] (`OTP_INVALID`, `ROLE_MISMATCH`, `USER_BLOCKED`).
  Future<LoginResult> verifyOtp({
    required String phone,
    required String code,
    required LoginRole role,
    DeviceInfo device = const DeviceInfo(),
  }) =>
      guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(
          '/auth/otp/verify',
          data: {'phone': phone, 'code': code, 'role': role.name, 'device': device.toJson()},
          options: _public,
        );
        return LoginResult.fromJson(res.data!);
      });

  /// `POST /auth/logout` (204): clears the FCM token and revokes refresh tokens.
  Future<void> logout() => guardApi(() => _client.dio.post<void>('/auth/logout'));
}
