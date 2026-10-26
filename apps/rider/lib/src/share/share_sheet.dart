import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with [text]. Returns false when sharing
/// is unavailable on the device.
typedef ShareSheet = Future<bool> Function({required String text, String? subject});

/// `share_plus` implementation.
Future<bool> systemShareSheet({required String text, String? subject}) async {
  try {
    final result = await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return result.status != ShareResultStatus.unavailable;
  } catch (e) {
    debugPrint('share sheet: $e');
    return false;
  }
}
