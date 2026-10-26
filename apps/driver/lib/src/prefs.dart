import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny key-value store for one-time flags.
abstract class AppPrefs {
  Future<bool> getBool(String key);

  Future<void> setBool(String key, bool value);
}

class SharedPrefsAppPrefs implements AppPrefs {
  @override
  Future<bool> getBool(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (e) {
      debugPrint('prefs: $e');
      return false;
    }
  }

  @override
  Future<void> setBool(String key, bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, value);
    } catch (e) {
      debugPrint('prefs: $e');
    }
  }
}

class MemoryAppPrefs implements AppPrefs {
  MemoryAppPrefs([Map<String, bool>? initial]) : _values = {...?initial};

  final Map<String, bool> _values;

  @override
  Future<bool> getBool(String key) async => _values[key] ?? false;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
}

/// Manufacturer name in lower case (`xiaomi`, `samsung`, …), or null.
Future<String?> readDeviceBrand() async {
  try {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final info = await DeviceInfoPlugin().androidInfo;
    final m = info.manufacturer.trim();
    return m.isEmpty ? info.brand.toLowerCase() : m.toLowerCase();
  } catch (e) {
    debugPrint('device info: $e');
    return null;
  }
}
