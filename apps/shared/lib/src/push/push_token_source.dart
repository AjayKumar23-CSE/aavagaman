import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Supplies the FCM registration token (SPEC §14: store and refresh tokens on
/// every app start).
abstract class PushTokenSource {
  /// Current token, or null when push is unavailable.
  Future<String?> getToken();

  /// Emits whenever FCM rotates the token.
  Stream<String> get onTokenRefresh;
}

/// Used when push is disabled and in tests.
class NoPushTokenSource implements PushTokenSource {
  const NoPushTokenSource();

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

/// Firebase Cloud Messaging.
///
/// TODO(firebase): there is no Firebase project yet. Until
/// `android/app/google-services.json` exists and the google-services Gradle
/// plugin is applied, [Firebase.initializeApp] fails; this class then
/// degrades silently (no crash, no token) and the apps keep working.
class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;
  Future<bool>? _ready;

  Future<bool> _ensureReady() => _ready ??= _init();

  Future<bool> _init() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp().timeout(timeout);
      // Android 13+ runtime permission (POST_NOTIFICATIONS).
      await FirebaseMessaging.instance.requestPermission().timeout(const Duration(seconds: 60));
      return true;
    } catch (e) {
      debugPrint('Push disabled: Firebase is not configured ($e)');
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    if (!await _ensureReady()) return null;
    try {
      return await FirebaseMessaging.instance.getToken().timeout(timeout);
    } catch (e) {
      debugPrint('FCM token unavailable ($e)');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh async* {
    if (!await _ensureReady()) return;
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }
}
