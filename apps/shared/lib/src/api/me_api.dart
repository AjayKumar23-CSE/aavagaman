import '../models/user.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// SPEC §7.2 profile endpoints (`/me`), used by both apps.
class MeApi {
  MeApi(this._client);

  final ApiClient _client;

  Future<User> get() => guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>('/me');
        return User.fromJson(res.data!);
      });

  /// `PATCH /me`. Null fields are left unchanged (the API cannot clear them).
  Future<User> update({String? name, String? email}) => guardApi(() async {
        final res = await _client.dio.patch<Map<String, dynamic>>('/me', data: {
          'name': ?name,
          'email': ?email,
        });
        return User.fromJson(res.data!);
      });

  Future<void> registerFcmToken(String token) =>
      guardApi(() => _client.dio.post<void>('/me/fcm-token', data: {'token': token}));

  /// `DELETE /me`: anonymises the account. 409 `ACTIVE_RIDE` during a ride.
  Future<void> delete() => guardApi(() => _client.dio.delete<void>('/me'));
}
