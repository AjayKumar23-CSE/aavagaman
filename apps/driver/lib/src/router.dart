import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';
import 'home_page.dart';
import 'pages/battery_guide_page.dart';
import 'pages/documents_page.dart';
import 'pages/earnings_page.dart';
import 'pages/history_page.dart';
import 'pages/info_pages.dart';
import 'pages/offer_page.dart';
import 'pages/pending_page.dart';
import 'pages/profile_page.dart';
import 'pages/registration_page.dart';
import 'pages/suspended_page.dart';
import 'pages/trip_page.dart';
import 'providers.dart';
import 'strings.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const phone = '/phone';
  static const otp = '/otp';
  static const register = '/register';
  static const documents = '/documents';
  static const pending = '/pending';
  static const suspended = '/suspended';
  static const home = '/home';
  static const offer = '/offer';
  static const trip = '/trip';
  static const battery = '/battery';
  static const profile = '/profile';
  static const help = '/help';
  static const privacy = '/privacy';
  static const earnings = '/earnings';
  static const history = '/history';

  static String otpFor(String phone) => Uri(path: otp, queryParameters: {'phone': phone}).toString();
}

/// Where onboarding must take the driver next (SPEC §12:
/// Registration → Documents → Pending approval → Home).
String gateFor(DriverProfile p) {
  if (p.verificationStatus == VerificationStatus.suspended) return Routes.suspended;
  if (p.needsRegistration) return Routes.register;
  if (p.verificationStatus == VerificationStatus.approved) return Routes.home;
  if (p.notUploaded.isNotEmpty) return Routes.documents;
  return Routes.pending;
}

/// Screens reachable in each onboarding state besides the gate itself.
const _allowed = {
  Routes.suspended: {Routes.help, Routes.privacy},
  Routes.register: {Routes.help, Routes.privacy},
  Routes.documents: {Routes.register, Routes.profile, Routes.help, Routes.privacy},
  Routes.pending: {Routes.documents, Routes.register, Routes.profile, Routes.help, Routes.privacy},
  Routes.home: {
    Routes.documents,
    Routes.profile,
    Routes.help,
    Routes.privacy,
    Routes.offer,
    Routes.trip,
    Routes.battery,
    Routes.earnings,
    Routes.history,
  },
};

/// Onboarding gate, then for approved drivers: open ride requests own the
/// screen (full-screen list, SPEC §12 / D-055), and a current or just-ended
/// ride replaces Home with the trip screen.
@visibleForTesting
String? driverRedirect(
  SessionState session,
  DriverProfile? profile,
  String location, {
  bool hasOffer = false,
  DriverRide? ride,
}) {
  switch (session) {
    case SessionUnknown():
      return location == Routes.splash ? null : Routes.splash;
    case SessionLoggedOut():
      return location == Routes.phone || location == Routes.otp ? null : Routes.phone;
    case SessionLoggedIn():
      // Profile still loading (or failed): Splash shows progress / retry.
      if (profile == null) return location == Routes.splash ? null : Routes.splash;
      final gate = gateFor(profile);
      if (gate == Routes.home) {
        if (hasOffer) return location == Routes.offer ? null : Routes.offer;
        if (location == Routes.offer) return ride != null ? Routes.trip : Routes.home;
        if (ride != null && location == Routes.home) return Routes.trip;
        if (ride == null && location == Routes.trip) return Routes.home;
      }
      if (location == gate || _allowed[gate]!.contains(location)) return null;
      return gate;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(driverProfileProvider, (_, _) => refresh.value++);
  ref.listen(offerProvider, (_, _) => refresh.value++);
  ref.listen(activeRideProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final to = driverRedirect(
        ref.read(sessionProvider),
        ref.read(driverProfileProvider).value,
        state.matchedLocation,
        hasOffer: ref.read(offerProvider).hasOffers,
        ride: ref.read(activeRideProvider).value,
      );
      if (to == null && state.matchedLocation == Routes.otp && state.uri.queryParameters['phone'] == null) {
        return Routes.phone;
      }
      return to;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (c, s) => const DriverSplashPage()),
      GoRoute(
        path: Routes.phone,
        builder: (c, s) => PhonePage(
          strings: AppLocalizations.of(c).common,
          role: LoginRole.driver,
          onCodeSent: (context, phone) => context.push(Routes.otpFor(phone)),
        ),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (c, s) => OtpPage(
          strings: AppLocalizations.of(c).common,
          role: LoginRole.driver,
          phone: s.uri.queryParameters['phone']!,
        ),
      ),
      GoRoute(path: Routes.register, builder: (c, s) => const RegistrationPage()),
      GoRoute(path: Routes.documents, builder: (c, s) => const DocumentsPage()),
      GoRoute(path: Routes.pending, builder: (c, s) => const PendingPage()),
      GoRoute(path: Routes.suspended, builder: (c, s) => const SuspendedPage()),
      GoRoute(path: Routes.home, builder: (c, s) => const HomePage()),
      GoRoute(path: Routes.offer, builder: (c, s) => const OfferPage()),
      GoRoute(path: Routes.trip, builder: (c, s) => const TripPage()),
      GoRoute(path: Routes.battery, builder: (c, s) => const BatteryGuidePage()),
      GoRoute(path: Routes.profile, builder: (c, s) => const ProfilePage()),
      GoRoute(path: Routes.help, builder: (c, s) => const HelpPage()),
      GoRoute(path: Routes.privacy, builder: (c, s) => const PrivacyPage()),
      GoRoute(path: Routes.earnings, builder: (c, s) => const EarningsPage()),
      GoRoute(path: Routes.history, builder: (c, s) => const DriverHistoryPage()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Session restore plus the first `GET /driver/me`.
class DriverSplashPage extends ConsumerWidget {
  const DriverSplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(driverProfileProvider);
    return SplashPage(
      strings: AppLocalizations.of(context).common,
      error: profile.hasError && !profile.isLoading ? profile.error : null,
      onRetry: () => ref.read(driverProfileProvider.notifier).reload(),
    );
  }
}
