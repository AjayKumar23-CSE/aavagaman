import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import 'ride_alert.dart';

/// Plays the bundled chime (`assets/sounds/ride_update.wav`, also
/// `res/raw/ride_update.wav` for the notification channel). Every call is
/// guarded: a missing plugin, no vibrator or a refused permission must never
/// break the ride screen.
class DeviceRideAlert implements RideAlert {
  DeviceRideAlert({required this.channelName, required this.channelDescription, AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  static const toneAsset = 'sounds/ride_update.wav';
  static const channelId = 'ride_updates';
  static const notificationId = 5151;
  static const vibrationPattern = [0, 250, 150, 250, 150, 450];

  final String channelName;
  final String channelDescription;
  final AudioPlayer _player;
  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Creates the high-importance channel with the chime. Call once at start.
  Future<void> setup() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
          sound: const RawResourceAndroidNotificationSound('ride_update'),
          enableVibration: true,
        ),
      );
    } catch (e) {
      debugPrint('ride alert setup: $e');
    }
  }

  @override
  Future<void> prepare() async {
    try {
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('notification permission: $e');
    }
  }

  @override
  Future<void> announce(RideAlertKind kind, {required String title, required String body, required bool inForeground}) async {
    if (!inForeground) {
      // The channel plays the chime and vibrates; playing it here too would double it.
      try {
        await _plugin.show(
          id: notificationId,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: channelDescription,
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.transport,
              sound: const RawResourceAndroidNotificationSound('ride_update'),
              autoCancel: true,
            ),
          ),
        );
      } catch (e) {
        debugPrint('ride notification: $e');
      }
      return;
    }
    try {
      await _player.stop();
      await _player.play(
        AssetSource(toneAsset),
        volume: 1,
        ctx: AudioContext(
          android: const AudioContextAndroid(
            // Notification stream: follows the phone's ringer/silent setting.
            usageType: AndroidUsageType.notificationEvent,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
    } catch (e) {
      debugPrint('ride chime: $e');
    }
    try {
      if (await Vibration.hasVibrator()) await Vibration.vibrate(pattern: vibrationPattern);
    } catch (e) {
      debugPrint('ride vibration: $e');
    }
  }
}
