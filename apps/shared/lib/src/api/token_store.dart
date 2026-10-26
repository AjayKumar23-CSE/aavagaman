import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_tokens.dart';

abstract class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// Persists tokens in the Android Keystore-backed secure storage.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'auth_tokens';
  final FlutterSecureStorage _storage;
  AuthTokens? _cache;

  @override
  Future<AuthTokens?> read() async {
    if (_cache != null) return _cache;
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return _cache = AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    _cache = tokens;
    await _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
  }

  @override
  Future<void> clear() async {
    _cache = null;
    await _storage.delete(key: _key);
  }
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._tokens]);

  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
