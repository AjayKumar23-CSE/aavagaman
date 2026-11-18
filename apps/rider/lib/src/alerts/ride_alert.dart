/// What the rider hears when the ride moves on: a driver accepted it, or
/// the driver reached the pickup.
enum RideAlertKind { accepted, arrived }

/// Chime + vibration while the app is open; a heads-up notification with
/// the same chime when it is in the background.
abstract class RideAlert {
  /// Asks for notification permission (Android 13+). Called when a ride is
  /// booked, so the question comes with an obvious reason.
  Future<void> prepare();

  Future<void> announce(RideAlertKind kind, {required String title, required String body, required bool inForeground});
}

/// No sound (tests).
class SilentRideAlert implements RideAlert {
  const SilentRideAlert();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> announce(RideAlertKind kind, {required String title, required String body, required bool inForeground}) async {}
}
