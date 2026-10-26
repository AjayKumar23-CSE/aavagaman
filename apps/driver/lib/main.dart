import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import 'l10n/app_localizations.dart';
import 'src/offers/audio_offer_alert.dart';
import 'src/presence/location_feed.dart';
import 'src/providers.dart';
import 'src/push/push_setup.dart';
import 'src/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));
  await setupNotifications();
  await BackgroundLocationFeed.configure(
    notificationTitle: l10n.onlineNotificationTitle,
    notificationBody: l10n.onlineNotificationBody,
  );
  await setupPush();
  final alert = AudioOfferAlert();
  await bootstrap(
    AppConfig.fromEnvironment(),
    () => ProviderScope(
      overrides: [offerAlertProvider.overrideWithValue(alert)],
      child: const App(),
    ),
  );
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Socket while logged in (SPEC §8) and foreground push re-sync (SPEC §14).
    ref.watch(realtimeConnectorProvider);
    ref.watch(pushBridgeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(brand: AppBrand.driver),
      darkTheme: AppTheme.dark(brand: AppBrand.driver),
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
