import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import 'offer_alert.dart';

/// Loops the bundled tone on the alarm stream and vibrates in a repeating
/// pattern until stopped. Every call is guarded: a missing plugin or a
/// phone without a vibrator must never break the offer flow.
class AudioOfferAlert implements OfferAlert {
  AudioOfferAlert({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  static const toneAsset = 'sounds/offer.wav';
  static const vibrationPattern = [0, 700, 400, 700, 600];

  final AudioPlayer _player;
  bool _playing = false;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(
        AssetSource(toneAsset),
        volume: 1,
        ctx: AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
            stayAwake: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('offer tone: $e');
    }
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: vibrationPattern, repeat: 0);
      }
    } catch (e) {
      debugPrint('vibration: $e');
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('offer tone stop: $e');
    }
    try {
      await Vibration.cancel();
    } catch (e) {
      debugPrint('vibration cancel: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
