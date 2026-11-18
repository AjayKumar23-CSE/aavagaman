import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'ride_alert.dart';

/// Silent by default; `main` puts in the device chime.
final rideAlertProvider = Provider<RideAlert>((ref) => const SilentRideAlert());

/// Rings when the active ride turns ACCEPTED (a driver took it, also after a
/// reassign) or ARRIVED, like Ola/Uber. Watched from `App`. Booking a ride
/// asks for notification permission so a backgrounded app can still ring.
final rideAlertListenerProvider = Provider<void>((ref) {
  ref.listen(activeRideProvider, (prev, next) {
    final before = prev?.value;
    final ride = next.value;
    if (ride == null) return;
    final alert = ref.read(rideAlertProvider);
    if (ride.status == RideStatus.requested && before?.id != ride.id) {
      unawaited(alert.prepare());
      return;
    }
    // Only a change seen live: opening the app on an accepted ride stays quiet.
    if (before == null || before.id != ride.id || before.status == ride.status) return;
    final kind = switch (ride.status) {
      RideStatus.accepted => RideAlertKind.accepted,
      RideStatus.arrived => RideAlertKind.arrived,
      _ => null,
    };
    if (kind == null) return;
    final l10n = lookupAppLocalizations(const Locale('en'));
    final name = ride.driver?.name;
    final driver = name == null || name.trim().isEmpty ? l10n.alertYourDriver : name.trim();
    final (title, body) = switch (kind) {
      RideAlertKind.accepted => (l10n.alertAcceptedTitle, l10n.alertAcceptedBody(driver)),
      RideAlertKind.arrived => (l10n.alertArrivedTitle, l10n.alertArrivedBody(driver)),
    };
    final state = WidgetsBinding.instance.lifecycleState;
    unawaited(alert.announce(kind, title: title, body: body, inForeground: state == null || state == AppLifecycleState.resumed));
  });
});
