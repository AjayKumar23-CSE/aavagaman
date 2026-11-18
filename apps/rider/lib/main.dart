import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import 'l10n/app_localizations.dart';
import 'src/alerts/device_ride_alert.dart';
import 'src/alerts/ride_alert_listener.dart';
import 'src/providers.dart';
import 'src/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));
  final alert = DeviceRideAlert(channelName: l10n.alertChannelName, channelDescription: l10n.alertChannelDescription);
  await alert.setup();
  await bootstrap(
    AppConfig.fromEnvironment(),
    () => ProviderScope(overrides: [rideAlertProvider.overrideWithValue(alert)], child: const App()),
  );
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Opens the realtime socket while logged in (SPEC §8).
    ref.watch(realtimeConnectorProvider);
    // Chime when a driver accepts or arrives.
    ref.watch(rideAlertListenerProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
