import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../presence/location_feed.dart';
import '../providers.dart';

/// Android notification channels (SPEC §14): `rides` is high importance with
/// the custom offer sound; `presence` carries the quiet "You are online"
/// foreground notification.
abstract final class NotificationChannels {
  static const rides = 'rides';
  static const presence = BackgroundLocationFeed.channelId;
  static const offerNotificationId = 4242;
}

final _plugin = FlutterLocalNotificationsPlugin();

/// English strings without a BuildContext (startup + background isolate).
AppLocalizations get _l10n => lookupAppLocalizations(const Locale('en'));

/// Creates the channels. Safe to call repeatedly and without the plugin
/// (tests, missing platform): failures are logged, never thrown.
Future<void> setupNotifications() async {
  try {
    final l10n = _l10n;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        NotificationChannels.rides,
        l10n.channelRidesName,
        description: l10n.channelRidesDescription,
        importance: Importance.max,
        sound: const RawResourceAndroidNotificationSound('offer'),
        enableVibration: true,
      ),
    );
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        NotificationChannels.presence,
        l10n.channelPresenceName,
        description: l10n.channelPresenceDescription,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );
  } catch (e) {
    debugPrint('Notifications unavailable: $e');
  }
}

/// Full-screen-intent notification so a locked phone shows the offer
/// (SPEC §12). Expires with the offer.
Future<void> showOfferNotification({required String rideId, String? pickup, DateTime? expiresAt}) async {
  try {
    final l10n = _l10n;
    final ttl = expiresAt?.difference(DateTime.now());
    await _plugin.show(
      id: NotificationChannels.offerNotificationId,
      title: l10n.offerTitle,
      body: l10n.offerNotificationBody(pickup ?? ''),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.rides,
          l10n.channelRidesName,
          channelDescription: l10n.channelRidesDescription,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          sound: const RawResourceAndroidNotificationSound('offer'),
          timeoutAfter: ttl == null || ttl.isNegative ? 20000 : ttl.inMilliseconds,
          autoCancel: true,
        ),
      ),
      payload: rideId,
    );
  } catch (e) {
    debugPrint('offer notification: $e');
  }
}

Future<void> cancelOfferNotification() async {
  try {
    await _plugin.cancel(id: NotificationChannels.offerNotificationId);
  } catch (_) {}
}

/// FCM data messages while the app is in the background / terminated
/// (SPEC §14): `ride_offer` → full-screen notification; `ride_status` just
/// wakes the app, which re-syncs over the socket when opened.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    final data = message.data;
    if (data['type'] == 'ride_offer' && data['ride_id'] is String) {
      await setupNotifications();
      await showOfferNotification(
        rideId: data['ride_id'] as String,
        pickup: message.notification?.body,
        expiresAt: asInstant(data['expires_at']),
      );
    }
  } catch (e) {
    debugPrint('background push: $e');
  }
}

/// Registers the background handler. Without a Firebase project
/// (no google-services.json) this fails quietly and the app runs on the
/// socket alone.
Future<void> setupPush() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    }
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  } catch (e) {
    debugPrint('Push disabled: Firebase is not configured ($e)');
  }
}

/// Foreground FCM messages: an offer or status push while the socket is
/// down means we missed something — reconnect and refresh.
final pushBridgeProvider = Provider<void>((ref) {
  StreamSubscription<RemoteMessage>? sub;
  try {
    sub = FirebaseMessaging.onMessage.listen((m) {
      final type = m.data['type'];
      final rt = ref.read(realtimeClientProvider);
      if (type == 'ride_offer') {
        if (!rt.isConnected) rt.connect(); // the server re-sends the open offer on connect
      } else if (type == 'ride_status') {
        ref.read(activeRideProvider.notifier).refresh();
      }
    }, onError: (Object e) => debugPrint('push stream: $e'));
  } catch (e) {
    debugPrint('Push bridge disabled: $e');
  }
  ref.onDispose(() => sub?.cancel());
});
