import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';
import 'home_page.dart';
import 'pages/confirm_page.dart';
import 'pages/history_page.dart';
import 'pages/info_pages.dart';
import 'pages/name_page.dart';
import 'pages/pick_on_map_page.dart';
import 'pages/profile_page.dart';
import 'pages/ride_detail_page.dart';
import 'pages/ride_page.dart';
import 'pages/set_drop_page.dart';
import 'providers.dart';
import 'strings.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const phone = '/phone';
  static const otp = '/otp';
  static const name = '/name';
  static const home = '/home';
  static const search = '/search';
  static const pickOnMap = '/pick';
  static const confirm = '/confirm';
  static const ride = '/ride';
  static const history = '/history';
  static const profile = '/profile';
  static const help = '/help';
  static const privacy = '/privacy';

  static String otpFor(String phone) => Uri(path: otp, queryParameters: {'phone': phone}).toString();

  static String historyDetail(String rideId) => '$history/$rideId';

  /// `for` = `pickup` | `drop`; [address] pre-fills the typed address.
  static String pickFor(String target, {String? address}) => Uri(
        path: pickOnMap,
        queryParameters: {'for': target, 'address': ?address},
      ).toString();
}

const _authFlow = {Routes.splash, Routes.phone, Routes.otp, Routes.name};

/// Screens that make no sense while a ride is in progress.
const _booking = {Routes.home, Routes.search, Routes.pickOnMap, Routes.confirm};

/// Session-driven navigation (SPEC §11: Splash → Phone → OTP → Name → Home),
/// plus: an active (or just-ended, undismissed) ride owns the screen.
@visibleForTesting
String? riderRedirect(
  SessionState session,
  String location, {
  AsyncValue<Ride?> activeRide = const AsyncData(null),
}) =>
    switch (session) {
      SessionUnknown() => location == Routes.splash ? null : Routes.splash,
      SessionLoggedOut() =>
        location == Routes.phone || location == Routes.otp ? null : Routes.phone,
      SessionLoggedIn(:final user) when user.needsName =>
        location == Routes.name ? null : Routes.name,
      SessionLoggedIn() => _authFlow.contains(location) ? Routes.home : _rideGate(activeRide, location),
    };

String? _rideGate(AsyncValue<Ride?> active, String location) {
  if (!active.hasValue) return null; // still loading: stay put
  final ride = active.value;
  if (ride != null && _booking.contains(location)) return Routes.ride;
  if (ride == null && location == Routes.ride) return Routes.home;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(activeRideProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final to = riderRedirect(
        ref.read(sessionProvider),
        state.matchedLocation,
        activeRide: ref.read(activeRideProvider),
      );
      if (to == null && state.matchedLocation == Routes.otp && state.uri.queryParameters['phone'] == null) {
        return Routes.phone;
      }
      return to;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (c, s) => SplashPage(strings: _strings(c))),
      GoRoute(
        path: Routes.phone,
        builder: (c, s) => PhonePage(
          strings: _strings(c),
          role: LoginRole.rider,
          onCodeSent: (context, phone) => context.push(Routes.otpFor(phone)),
        ),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (c, s) => OtpPage(
          strings: _strings(c),
          role: LoginRole.rider,
          phone: s.uri.queryParameters['phone']!,
        ),
      ),
      GoRoute(path: Routes.name, builder: (c, s) => const NamePage()),
      GoRoute(path: Routes.home, builder: (c, s) => const HomePage()),
      GoRoute(path: Routes.search, builder: (c, s) => const SetDropPage()),
      GoRoute(
        path: Routes.pickOnMap,
        builder: (c, s) => PickOnMapPage(
          forPickup: s.uri.queryParameters['for'] == 'pickup',
          initialAddress: s.uri.queryParameters['address'],
        ),
      ),
      GoRoute(path: Routes.confirm, builder: (c, s) => const ConfirmPage()),
      GoRoute(path: Routes.ride, builder: (c, s) => const RidePage()),
      GoRoute(
        path: Routes.history,
        builder: (c, s) => const HistoryPage(),
        routes: [
          GoRoute(path: ':id', builder: (c, s) => RideDetailPage(rideId: s.pathParameters['id']!)),
        ],
      ),
      GoRoute(path: Routes.profile, builder: (c, s) => const ProfilePage()),
      GoRoute(path: Routes.help, builder: (c, s) => const HelpPage()),
      GoRoute(path: Routes.privacy, builder: (c, s) => const PrivacyPage()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

CommonStrings _strings(BuildContext context) => AppLocalizations.of(context).common;
