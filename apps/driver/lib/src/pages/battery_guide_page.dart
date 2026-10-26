import 'package:android_intent_plus/android_intent.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';

enum PhoneBrand { xiaomi, vivo, oppo, realme, samsung, other }

/// Maps `Build.MANUFACTURER` / brand to the OEMs with aggressive battery
/// managers (SPEC §12).
PhoneBrand brandFor(String? manufacturer) {
  final m = (manufacturer ?? '').toLowerCase();
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) return PhoneBrand.xiaomi;
  if (m.contains('vivo') || m.contains('iqoo')) return PhoneBrand.vivo;
  if (m.contains('realme')) return PhoneBrand.realme;
  if (m.contains('oppo') || m.contains('oneplus')) return PhoneBrand.oppo;
  if (m.contains('samsung')) return PhoneBrand.samsung;
  return PhoneBrand.other;
}

/// One-time guide to disable battery optimisation, with deep links.
class BatteryGuidePage extends ConsumerWidget {
  const BatteryGuidePage({super.key});

  static const packageName = 'com.rideplatform.driver';

  Future<void> _openBatterySettings() async {
    try {
      await const AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$packageName',
      ).launch();
      return;
    } catch (e) {
      debugPrint('battery intent: $e');
    }
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
    } catch (e) {
      debugPrint('battery settings: $e');
    }
  }

  Future<void> _openAppSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (e) {
      debugPrint('app settings: $e');
    }
  }

  Future<void> _done(BuildContext context, WidgetRef ref) async {
    await ref.read(batteryGuideSeenProvider.notifier).markSeen();
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final brand = brandFor(ref.watch(deviceBrandProvider).value);
    final (brandName, note) = switch (brand) {
      PhoneBrand.xiaomi => ('Xiaomi / Redmi / POCO', l10n.batteryXiaomi),
      PhoneBrand.vivo => ('Vivo / iQOO', l10n.batteryVivo),
      PhoneBrand.oppo => ('OPPO / OnePlus', l10n.batteryOppo),
      PhoneBrand.realme => ('Realme', l10n.batteryRealme),
      PhoneBrand.samsung => ('Samsung', l10n.batterySamsung),
      PhoneBrand.other => (null, null),
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.batteryTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.battery_saver, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(l10n.batteryIntro, style: text.bodyLarge),
          const SizedBox(height: 16),
          Text(l10n.batteryGenericSteps),
          if (note != null) ...[
            const SizedBox(height: 16),
            Text(l10n.batteryBrandNote(brandName!), style: text.titleMedium),
            const SizedBox(height: 4),
            Text(note, key: const Key('brand-note')),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openBatterySettings,
            icon: const Icon(Icons.settings),
            label: Text(l10n.batteryOpenSettings),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _openAppSettings, child: Text(l10n.batteryOpenAppSettings)),
          const SizedBox(height: 16),
          TextButton(onPressed: () => _done(context, ref), child: Text(l10n.batteryDone)),
        ],
      ),
    );
  }
}
